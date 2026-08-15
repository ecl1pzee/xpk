//! rollbacks, function pretty simmilar to remove actually, all it does is just look for a layer you specify, and relink to those
const std = @import("std");
const globals = @import("../globals.zig");
const utils = @import("../utils/utils.zig");
const db = @import("../db/db.zig");
const snapshots = @import("../db/snapshots.zig");
const systreef = @import("../systree/systree.zig");
const log = @import("../utils/log.zig");

const Owner = struct {
    repo: utils.parser.Repo,
    entry: db.Dbentry,
};

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

fn prev_gen(io: std.Io, allocator: std.mem.Allocator, reponame: []const u8, pkgname: []const u8, currentgen: u32) !?u32 {
    const pkgdir = try std.fs.path.join(allocator, &.{ globals.snapshots, reponame, pkgname });
    defer allocator.free(pkgdir);

    var dir = std.Io.Dir.openDirAbsolute(io, pkgdir, .{ .iterate = true }) catch |err| switch (err) {
        error.FileNotFound => return null,
        else => return err,
    };
    defer dir.close(io);

    var best: ?u32 = null;

    var it = dir.iterate();
    while (try it.next(io)) |entry| {
        if (entry.kind != .directory) continue;
        if (!std.mem.startsWith(u8, entry.name, "layer-")) continue;

        const num = std.fmt.parseInt(u32, entry.name["layer-".len..], 10) catch continue;
        if (num >= currentgen) continue;

        if (best == null or num > best.?) best = num;
    }

    return best;
}

pub fn rollback_pkg(io: std.Io, allocator: std.mem.Allocator, pkgname: []const u8, targetgen: ?u32) !void {
    log.trace("rolling back {s}\n", .{pkgname});

    const reposbytes = try std.Io.Dir.cwd().readFileAlloc(io, globals.reposconf, allocator, .unlimited);
    defer allocator.free(reposbytes);

    const repos = try utils.parser.parse_r(allocator, reposbytes);
    defer allocator.free(repos);

    const owner = try find_owner(io, allocator, repos, pkgname) orelse {
        log.warn("{s} is not installed\n", .{pkgname});
        return error.notinstalled;
    };

    const gen = targetgen orelse (try prev_gen(io, allocator, owner.repo.name, pkgname, owner.entry.generation)) orelse {
        log.warn("no earlier generation of {s} to roll back to\n", .{pkgname});
        return error.nopreviousgeneration;
    };

    const gendir = try snapshots.generation_path(allocator, owner.repo.name, pkgname, gen);
    defer allocator.free(gendir);

    var checkfile = std.Io.Dir.openDirAbsolute(io, gendir, .{}) catch |err| switch (err) {
        error.FileNotFound => {
            log.warn("layer-{d} of {s} doesn't exist on disk\n", .{ gen, pkgname });
            return error.generationnotfound;
        },
        else => return err,
    };
    checkfile.close(io);

    log.debug1("pointing {s} at layer-{d}\n", .{ pkgname, gen });
    try snapshots.activate_generation(io, allocator, owner.repo.name, pkgname, gendir);

    const markerpath = try std.fs.path.join(allocator, &.{ gendir, snapshots.treehashm });
    defer allocator.free(markerpath);

    const hex = try std.Io.Dir.cwd().readFileAlloc(io, markerpath, allocator, .limited(256));
    defer allocator.free(hex);

    var treehash: [32]u8 = undefined;
    _ = try std.fmt.hexToBytes(&treehash, std.mem.trim(u8, hex, " \n\r\t"));

    log.debug2("merging rolled back tree into {s}\n", .{globals.base});
    try snapshots.merge_tree(io, allocator, owner.repo.name, pkgname, treehash);

    try systreef.seal_systree(io, allocator, pkgname, .rollback);

    log.success("rolled back {s} to layer-{d}\n", .{ pkgname, gen });
}

pub fn rollback_sys(io: std.Io, allocator: std.mem.Allocator, targetnum: ?u32) !void {
    log.trace("rolling back whole system\n", .{});

    var num = targetnum;

    if (num == null) {
        const entries = try systreef.read_log(io, allocator);
        defer {
            for (entries) |e| allocator.free(e.pkgname);
            allocator.free(entries);
        }

        if (entries.len < 2) {
            log.warn("not enough systree's sealed to roll back\n", .{});
            return error.noprevioussystree;
        }

        num = entries[entries.len - 2].systreenum;
    }

    try systreef.revert_systree(io, allocator, num.?);

    var currentdir = try std.Io.Dir.openDirAbsolute(io, globals.current, .{ .iterate = true });
    defer currentdir.close(io);

    var repoit = currentdir.iterate();
    while (try repoit.next(io)) |repoentry| {
        if (repoentry.kind != .directory) continue;

        const repopath = try std.fs.path.join(allocator, &.{ globals.current, repoentry.name });
        defer allocator.free(repopath);

        var repodir = try std.Io.Dir.openDirAbsolute(io, repopath, .{ .iterate = true });
        defer repodir.close(io);

        var pkgit = repodir.iterate();
        while (try pkgit.next(io)) |pkgentry| {
            if (pkgentry.kind != .sym_link) continue;

            const linkpath = try std.fs.path.join(allocator, &.{ repopath, pkgentry.name });
            defer allocator.free(linkpath);

            var buf: [std.fs.max_path_bytes]u8 = undefined;
            const len = try std.Io.Dir.readLinkAbsolute(io, linkpath, &buf);
            const gendir = buf[0..len];

            const markerpath = try std.fs.path.join(allocator, &.{ gendir, snapshots.treehashm });
            defer allocator.free(markerpath);

            const hex = std.Io.Dir.cwd().readFileAlloc(io, markerpath, allocator, .limited(256)) catch continue;
            defer allocator.free(hex);

            var treehash: [32]u8 = undefined;
            _ = std.fmt.hexToBytes(&treehash, std.mem.trim(u8, hex, " \n\r\t")) catch continue;

            try snapshots.merge_tree(io, allocator, repoentry.name, pkgentry.name, treehash);
        }
    }

    try systreef.seal_systree(io, allocator, "system", .rollback);

    log.success("system rolled back\n", .{});
}