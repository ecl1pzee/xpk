const std = @import("std");
const utils = @import("../utils/utils.zig");
const types = @import("types/types.zig");
const log = @import("../utils/log.zig");
const Ed25519 = std.crypto.sign.Ed25519;
const sign = @import("../security/keygen.zig").sign;
const print = std.debug.print;

// magic bytes for index.bin, so you can instantly tell from a xxd/hexdump, and because it looks fucking awesome and cool tbh
const magic = "XPKI";
const formatvers: u16 = 1;

// i need these guys, since we are actually writing hex now
inline fn writeU16(list: *std.ArrayList(u8), allocator: std.mem.Allocator, val: u16) !void {
    var buf: [2]u8 = undefined;
    std.mem.writeInt(u16, &buf, val, .little);
    try list.appendSlice(allocator, &buf);
}

inline fn writeU32(list: *std.ArrayList(u8), allocator: std.mem.Allocator, val: u32) !void {
    var buf: [4]u8 = undefined;
    std.mem.writeInt(u32, &buf, val, .little);
    try list.appendSlice(allocator, &buf);
}

// encodes the whole entry list into the index.bin, and head commit for version pinning
//   magic here (which is xpki) | version u16 | count u32 | offsets[amount of count] u32 (sorted by name) | entries... | crc32 u32, the crc is required at the end to make sure the file isnt truncated, this can reallylyyyyy easily tell wether there is a crc mismatch with crc hashing
fn encode_idx(allocator: std.mem.Allocator, entries: []types.Idxentry, head: [32]u8) ![]u8 {
    //alphabetic. no real use, but its much cleaner for a literal binary searcher
    std.mem.sort(types.Idxentry, entries, {}, struct {
        fn lessThan(_: void, a: types.Idxentry, b: types.Idxentry) bool {
            return std.mem.order(u8, a.name, b.name) == .lt;
        }
    }.lessThan);

    // encode entries standalone, so we know length for offset table
    var entriesblob: std.ArrayList([]u8) = .empty;
    defer {
        for (entriesblob.items) |blob| allocator.free(blob);
        entriesblob.deinit(allocator);
    }

    for (entries) |entry| {
        const blob = try entry.encode(allocator);
        try entriesblob.append(allocator, blob);
    }

    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(allocator);

    try out.appendSlice(allocator, magic);
    try writeU16(&out, allocator, formatvers);
    try out.appendSlice(allocator, &head); // fixed 32 bytes, if its padded sure fine, if its not padded then great, i recommend yall to use git sha-256, since i support it
    try writeU32(&out, allocator, @intCast(entries.len));

    // offset table 
    var roffs: u32 = 0;
    for (entriesblob.items) |blob| {
        try writeU32(&out, allocator, roffs);
        roffs += @intCast(blob.len);
    }

    for (entriesblob.items) |blob| {
        try out.appendSlice(allocator, blob);
    }

    // crc32 over everything written so far, because resolvers can tell this one, and its pretty unique??? 
    const crc = std.hash.Crc32.hash(out.items);
    try writeU32(&out, allocator, crc);

    return out.toOwnedSlice(allocator);
}

// basically a wrapper around the index.bin which lets us add a signature to show antitamper.
// since its a wrapper, encode idx actually has no idea this part even exists
pub fn wrap_signed(allocator: std.mem.Allocator, indexbin: []const u8, sigs: []const types.Sigentry) ![]u8 {
    if (sigs.len > 255) return error.toomanysigners; // sigcount is u8, 255 signers is already absurd for any repo

    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(allocator);

    try writeU32(&out, allocator, @intCast(indexbin.len));
    try out.appendSlice(allocator, indexbin);
    // appneds fingerprint and signature to indexbin
    try out.append(allocator, @intCast(sigs.len));
    for (sigs) |s| {
        try out.appendSlice(allocator, &s.fingerprint);
        try out.appendSlice(allocator, &s.signature);
    }

    return out.toOwnedSlice(allocator);
}
// indexes a repo from a path and recursively generates a idxentry per package, also has someee debug output but ill prob wire up alot more 
// now writes its own binary format (index.bin) instead of json
// this is more of a developer exclusive use tool, as its made for generating repos instead of updating, however users can obviously just use this tool to wire up their own repos
// recent add: hashing for individual xbuilds
// and, this is literally a dev tool so i fear log.info=log.trace here, but ill add some debugging anyawys
pub fn index_repo(io: std.Io, allocator: std.mem.Allocator, repopath: []const u8, kp: Ed25519.KeyPair) !void {
    var entries: std.ArrayList(types.Idxentry) = .empty;
    defer entries.deinit(allocator);
    // fuck
    
    var dir = try std.Io.Dir.openDirAbsolute(io, repopath, .{ .iterate = true });
    defer dir.close(io);

    var categories = dir.iterate();

    while (try categories.next(io)) |category| {
        if (category.kind != .directory) continue;
        if (category.name.len > 0 and category.name[0] == '.') continue; // skip .git, .github, any dotfiles because they arent meant to contain anything, this broke indexing especially after fecthing packages from repo and tryna index and add

        const categorypath = try std.fs.path.join(allocator, &.{ repopath, category.name });
        defer allocator.free(categorypath);

        var catdir = try std.Io.Dir.openDirAbsolute(io, categorypath, .{ .iterate = true });
        defer catdir.close(io);

        var packages = catdir.iterate();

        while (try packages.next(io)) |package| {
            if (package.kind != .directory) continue;
            if (package.name.len > 0 and package.name[0] == '.') continue; // same guard as mentioned before

            const buildpath = try std.fs.path.join(allocator, &.{ categorypath, package.name, "xbuild" });
            defer allocator.free(buildpath);

            const bytes = std.Io.Dir.cwd().readFileAlloc(io, buildpath, allocator, .unlimited) catch |err| switch (err) {
                error.FileNotFound => {
                    log.warn("{s}/{s} has no xbuild, skipping\n", .{ category.name, package.name }); 
                    continue;
                }, else => return err,
            };
            defer allocator.free(bytes);       
            
            // this will fail if not all requirements for [pkg] and [build] are satisfied too, however i think thats fine for right now or maybe long term before we get 'just' binaries, plus we need a repo for that
            const xbuild = try utils.parser.parse_a(allocator, bytes);
    
            // desc is optional in the type, but the index wants a string for every entry.
            // rather than force unwrap and panic the whole index run over one sloppy package, it just empties it and warns so you actually write a desc
            const desc = xbuild.info.desc orelse blk: {
                log.warn("{s}/{s} has no desc in xbuild, defaulting to nothing\n", .{ category.name, package.name },);
                break :blk ""; // break loop, i hate that syntax 
            };

            // appends everything so it can put it into the binary blob, unrolled for readability 
            log.trace("appending all entries...\n", .{});
            try entries.append(allocator, .{
                .xhash = try utils.security.get_hashb(bytes),
                .name = try allocator.dupe(u8, xbuild.info.name),
                .category = try allocator.dupe(u8, category.name),
                .version = try allocator.dupe(u8, xbuild.info.version),
                .description = try allocator.dupe(u8, desc),
            });

            // nice to just do this
            log.info("{s}/{s} indexed\n", .{ category.name, package.name });
        }
    }

    // here that happens, we encode the blob 
    log.trace("encoding binary blob and getting head\n", .{});
    const head = try get_head(io, allocator, repopath);
    const indexbin = try encode_idx(allocator, entries.items, head); 
    defer allocator.free(indexbin);

    // sign raw body, then its wrapped and easily unwrapped
    log.trace("signing index\n", .{});
    const sigbytes = try sign(kp, indexbin);
    const sigs = [_]types.Sigentry{.{
        .fingerprint = kp.public_key.toBytes(),
        .signature = sigbytes,
    }};
    

    const wrapped = try wrap_signed(allocator, indexbin, &sigs);
    defer allocator.free(wrapped);

    const idxbin = try std.fmt.allocPrint(allocator, "{s}/index", .{repopath});
    defer allocator.free(idxbin);

    // final things + write stuff
    const indexfile = try std.Io.Dir.createFileAbsolute(io, idxbin, .{ .truncate = true });
    defer indexfile.close(io);

    var writerbuf: [16 * 1024]u8 = undefined;
    var writer = indexfile.writer(io, &writerbuf);

    try writer.interface.writeAll(wrapped); 
    try writer.interface.flush();

    // also, later ill add a compression to the index.bin so for even more packages its compressed and is so much faster to download
    // but ill do it only when we have like 30 packages
    log.info("indexed {d} packages, signed with fingerprint {x}\n", .{ entries.items.len, kp.public_key.toBytes() });
}

// gets head directly from file so we dont use git as a dep,
// but you do need a git initialized for this to work, otherwise its just gonna fail at line at headfile
fn get_head(io: std.Io, allocator: std.mem.Allocator, repopath: []const u8) ![32]u8 { // :drooling emoji:
    const gheadpath = try std.fs.path.join(allocator, &.{ repopath, ".git", "HEAD" });
    defer allocator.free(gheadpath);

    const headfile = try std.Io.Dir.cwd().readFileAlloc(
        io,
        gheadpath,
        allocator,
        .unlimited,
    );
    defer allocator.free(headfile);

    const head = std.mem.trim(u8, headfile, " \n\r\t");

    var hashedtext: []const u8 = undefined;

    if (std.mem.startsWith(u8, head, "ref: ")) {
        // normal branch
        const ref = std.mem.trim(u8, head["ref: ".len..], " \n\r\t");

        const refpath = try std.fs.path.join(
            allocator,
            &.{ repopath, ".git", ref },
        );
        defer allocator.free(refpath);

        const reffile = try std.Io.Dir.cwd().readFileAlloc(
            io,
            refpath,
            allocator,
            .unlimited,
        );
        

        hashedtext = std.mem.trim(u8, reffile, " \n\r\t");
    } else {
        // detached HEAD, hash is directly in HEAD, we usually dont want this though
        hashedtext = head;
    }
    // very crude use of memset tbh, butyeah itt works
    var result: [32]u8 = undefined;
    @memset(&result, 0);
   
   // logic checking for sha types
    if (hashedtext.len == 40) {
    // sha1
        var sha1: [20]u8 = undefined;
        _ = try std.fmt.hexToBytes(&sha1, hashedtext);
        @memset(&result, 0);
        @memcpy(result[0..20], &sha1); // for sha1
    } else if (hashedtext.len == 64) {
    // sha256 (just for support), and we lowk wan it
        _ = try std.fmt.hexToBytes(&result, hashedtext); // sha256
    } else { 
        return error.invalidcommithash;
    }
    

    return result;
}