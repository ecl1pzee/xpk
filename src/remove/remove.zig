//! removal: unlinks a package's symlinks from globals.base, deletes its shit. easy.
//! rewritten for new ostree approach
const std = @import("std");
const globals = @import("../globals.zig");
const db = @import("../db/db.zig");
const objects = @import("../db/objects.zig");
const utils = @import("../utils/utils.zig");
const log = @import("../utils/log.zig");

pub const Removeerror = error{notinstalled};

const Owner = struct {
    repo: utils.parser.Repo,
    entry: db.Dbentry,
};

// finds owner and deletes
fn find_owner(io: std.Io, allocator: std.mem.Allocator, repos: []const utils.parser.Repo, name: []const u8) !?Owner {
    var found: ?Owner = null;
    var foundp: i32 = std.math.minInt(i32);

    for (repos) |repo| {
        const entries = db.read_w(io, allocator, repo.name) catch |err| {
            log.warn("failed reading database '{s}': {s}\n", .{ repo.name, @errorName(err) });
            continue;
        };
        defer allocator.free(entries);

        const entry = db.current_e(entries, name) orelse continue;

        if (repo.priority > foundp) {
            found = .{ .repo = repo, .entry = entry };
            foundp = repo.priority;
        }
    }

    return found;
}

// missing symlinks are warned
fn unlink_paths(io: std.Io, allocator: std.mem.Allocator, entries: []const objects.Treeentry) !void {
    for (entries) |e| {
        const linkpath = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ globals.base, e.crel });
        defer allocator.free(linkpath);

        std.Io.Dir.deleteFileAbsolute(io, linkpath) catch |err| switch (err) {
            error.FileNotFound => {
                log.warn("{s} was already missing, skipping\n", .{linkpath});
            },
            else => return err,
        };

        log.debug2("unlinked {s}\n", .{linkpath});
    }
}

// the actual remove operation
pub fn remove(io: std.Io, allocator: std.mem.Allocator, pkgname: []const u8) !void {
    log.trace("starting removal of {s}\n", .{pkgname});

    const reposbytes = try std.Io.Dir.cwd().readFileAlloc(io, globals.reposconf, allocator, .unlimited);
    defer allocator.free(reposbytes);

    const repos = try utils.parser.parse_r(allocator, reposbytes);
    defer allocator.free(repos);

    const owner = try find_owner(io, allocator, repos, pkgname) orelse {
        log.warn("{s} is not installed\n", .{pkgname});
        return Removeerror.notinstalled;
    };

    log.debug1("{s} is owned by repo '{s}'\n", .{ pkgname, owner.repo.name });

    var loaded = try objects.load_tree(io, allocator, owner.entry.objhash);
    defer loaded.deinit(allocator);

    log.trace("unlinking {d} paths\n", .{loaded.entries.len});
    try unlink_paths(io, allocator, loaded.entries);

    try db.remove_i(io, allocator, owner.repo.name, pkgname);

    log.success("removed {s}\n", .{pkgname});
}