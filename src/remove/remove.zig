//! removal: unlinks a package's symlinks from globals.base, deletes its shit. easy.
const std = @import("std");
const globals = @import("../globals.zig");
const db = @import("../db/db.zig");
const manifest = @import("../install/types/types.zig");
const utils = @import("../utils/utils.zig");
const log = @import("../utils/log.zig");

pub const Removeerror = error{ notinstalled, nomanifest };

// finds the repo package is installed in
fn find_owner(io: std.Io, allocator: std.mem.Allocator, repos: []const utils.parser.Repo, name: []const u8) !?utils.parser.Repo {
    var found: ?utils.parser.Repo = null;
    var foundp: i32 = std.math.minInt(i32);

    for (repos) |repo| {
        const entries = db.read_w(io, allocator, repo.name) catch |err| {
            log.warn("failed reading database '{s}': {s}\n", .{ repo.name, @errorName(err) });
            continue;
        };
        defer allocator.free(entries);

        if (db.current_e(entries, name) == null) continue;

        if (repo.priority > foundp) {
            found = repo;
            foundp = repo.priority;
        }
    }

    return found;
}

// reads a package's file manifest, returning the crel paths that were symlinked
fn read_manifest(io: std.Io, allocator: std.mem.Allocator, reponame: []const u8, pkgname: []const u8) ![][]const u8 {
    const manifestpath = try std.fs.path.join(allocator, &.{ globals.db, reponame, "files", pkgname });
    defer allocator.free(manifestpath);

    const bytes = std.Io.Dir.cwd().readFileAlloc(io, manifestpath, allocator, .unlimited) catch |err| switch (err) {
        error.FileNotFound => return Removeerror.nomanifest,
        else => return err,
    };
    defer allocator.free(bytes);

    const borrowed = try manifest.parse_m(bytes, allocator);
    defer allocator.free(borrowed);

    const owned = try allocator.alloc([]const u8, borrowed.len);
    errdefer allocator.free(owned);
    for (borrowed, 0..) |p, i| owned[i] = try allocator.dupe(u8, p);

    return owned;
}

// unlinks every crel path's symlink from globals.base. missing symlinks.
fn unlink_paths(io: std.Io, allocator: std.mem.Allocator, paths: []const []const u8) !void {
    for (paths) |crel| {
        const linkpath = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ globals.base, crel });
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

// deletes the manifest file itself, once its contents have been unlinked.
fn delete_manifest(io: std.Io, allocator: std.mem.Allocator, reponame: []const u8, pkgname: []const u8) !void {
    const manifestpath = try std.fs.path.join(allocator, &.{ globals.db, reponame, "files", pkgname });
    defer allocator.free(manifestpath);

    std.Io.Dir.deleteFileAbsolute(io, manifestpath) catch |err| switch (err) {
        error.FileNotFound => {},
        else => return err,
    };
}

// the actual remove operation: resolve owner -> unlink symlinks -> delete
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

    log.debug1("{s} is owned by repo '{s}'\n", .{ pkgname, owner.name });

    const paths = read_manifest(io, allocator, owner.name, pkgname) catch |err| switch (err) {
        Removeerror.nomanifest => {
            log.warn("no manifest found for {s}, only cleaning up db entries\n", .{pkgname});
            try db.remove_i(io, allocator, owner.name, pkgname);
            return;
        },
        else => return err,
    };
    defer {
        for (paths) |p| allocator.free(p);
        allocator.free(paths);
    }

    log.trace("unlinking {d} paths\n", .{paths.len});
    try unlink_paths(io, allocator, paths);

    try delete_manifest(io, allocator, owner.name, pkgname);

    try db.remove_i(io, allocator, owner.name, pkgname);

    log.success("removed {s}\n", .{pkgname});
}