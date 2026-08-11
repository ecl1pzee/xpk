//! rework
//! remote fetch now assumes index is local, helps with speeds a lot because we split downloads on repos
//! switched index.json to index.bin, own format now. yay.
//! yeah.

const std = @import("std");
const types = @import("types/types.zig");
const globals = @import("../globals.zig");
const downloader = @import("../downloader/downloader.zig");
const utils = @import("../utils/utils.zig");
const log = @import("../utils/log.zig");

const print = std.debug.print;

fn build_url(allocator: std.mem.Allocator, repourl: []const u8, headstr: []const u8, subpath: []const u8) ![]u8 {
    if (std.mem.indexOf(u8, repourl, "github") != null) {
        const branchstart = std.mem.lastIndexOfScalar(u8, repourl, '/') orelse {
            // no '/' found at all, malformed url, just fall through unpinned, and probably fail
            return try std.fmt.allocPrint(allocator, "{s}/{s}", .{ repourl, subpath });
        };
        const base = repourl[0..branchstart];
        return try std.fmt.allocPrint(allocator, "{s}/{s}/{s}", .{ base, headstr, subpath });
    }

    // add elsestatemnts for codeberg.org / raw.codeberg.org uses a different raw-url shape

    // unknown host, so just return normally
    return try std.fmt.allocPrint(allocator, "{s}/{s}", .{ repourl, subpath });
}

// taken from neo, only thing implemented new is the limit, so malicious gigantic package specs/infos cant lag you (unless you are lacking 8192 bytes of ram)
fn fetchraw(allocator: std.mem.Allocator, io: std.Io, url: []const u8) ![]u8 {
    var client = std.http.Client{ .allocator = allocator, .io = io };
    defer client.deinit();

    const uri = try std.Uri.parse(url);
    var req = try client.request(.GET, uri, .{});
    defer req.deinit();
    try req.sendBodiless();

    var redirectbuf: [1024]u8 = undefined;
    var response = try req.receiveHead(&redirectbuf);

    var transferbuf: [4096]u8 = undefined;
    var decompbuf: [65536]u8 = undefined;
    var decomp: std.http.Decompress = undefined;
    const reader = response.readerDecompressing(&transferbuf, &decomp, &decompbuf);

    return try reader.allocRemaining(allocator, .limited(64 * 1024));
}

fn format_head(allocator: std.mem.Allocator, head: [32]u8) ![]u8 {
    const issha1 = std.mem.allEqual(u8, head[20..32], 0);
    const len: usize = if (issha1) 20 else 32;

    return try std.fmt.allocPrint(allocator, "{x}", .{head[0..len]});
}

// checks your indexes from each repo
pub fn remote_fetch(io: std.Io, allocator: std.mem.Allocator, package: []const u8) !types.Pkgurl {
    const reposbytes = try std.Io.Dir.cwd().readFileAlloc(io, globals.reposconf, allocator, .unlimited);
    defer allocator.free(reposbytes);

    const repos = try utils.parser.parse_r(allocator, reposbytes);

    // we use invidial ones instead of 'foundrepo' because with foundrepo it fucks over after
    var foundreponame: ?[]u8 = null;
    var foundrepourl: ?[]u8 = null;
    var foundpkg: ?types.Idxentry = null;
    var foundhead: [32]u8 = undefined;

    log.trace("going through repos\n", .{});
    for (repos) |repo| {
        if (!repo.enabled) continue;

        const indexpath = try std.fs.path.join(allocator, &.{ globals.local, repo.name, "index" });
        defer allocator.free(indexpath);

        // we dont free here for a REASON its in a FOR LOOP
        const indexbytes = std.Io.Dir.cwd().readFileAlloc(io, indexpath, allocator, .unlimited) catch continue;

        const parsed = types.parse_idx(indexbytes, allocator) catch |err| {
            log.warn("{s}'s index is malformed ({s}), skipping repo\n", .{ repo.name, @errorName(err) });
            continue;
        };
        defer allocator.free(parsed.offsets); // we free these cuz we don't need allat after the for statement

        // uses the parsed offset table and find_package to find the package
        if (types.find_package(indexbytes, parsed.offsets, parsed.entriesst, package)) |entry| {
            foundreponame = try allocator.dupe(u8, repo.name);
            foundrepourl = try allocator.dupe(u8, repo.url);

            foundpkg = entry;
            foundhead = parsed.head;
            break;
        }
    }

    // fixed unreachable shit
    const pkg = foundpkg orelse {
        log.warn("package {s} doesn't exist in any enabled repo\n", .{package});
        std.process.exit(1); // errors that happen a lot are ugly, thats why std.process.exit is used to not let that happen
    };

    const reponame = foundreponame orelse unreachable; // safe now
    const repourl = foundrepourl orelse unreachable;

    log.trace("formatting urls\n", .{});

    // formats head for sha1/sha256 git head, since xpk-c currently uses sha1, we just do that, but it supports repos with git sha-256!
    const headstr = try format_head(allocator, foundhead);
    defer allocator.free(headstr);

    const path = try std.fmt.allocPrint(allocator, "{s}/{s}/xbuild", .{ pkg.category, pkg.name });
    defer allocator.free(path);

    // pins the fetch to the exact commit the index was generated from instead of just getting things from latest commit, this is good for both safety and reliablity, because syncing = downloading a newer commit with newer hash, which means newer versions, unlike old syncing that was just adding packages
    const xbuildurl = try build_url(allocator, repourl, headstr, path);
    defer allocator.free(xbuildurl);

    log.info("getting remote build files...\n", .{});

    //errordefers and added a hash getter, and hash formatter for index.bin
    const xbuildbytes = try fetchraw(allocator, io, xbuildurl);
    errdefer allocator.free(xbuildbytes);
    // so our security is not only per repo it is per package, although hashes do not have a use for being individually signed, its much better to just sign the repo
    const avhash = try utils.security.get_hashb(xbuildbytes);

    if (!std.mem.eql(u8, &avhash, &pkg.xhash)) {
        log.err("hash of package in index does not match the one that was downloaded\n", .{});
        return error.xbuildhashmismatch;
    }

    // need more shit
    return types.Pkgurl{ .allocator = allocator, .xbuild = xbuildbytes, .repo = reponame, .category = pkg.category, .hash = pkg.xhash };
}
