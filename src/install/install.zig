//! installs stuff professionally, and records it in the db, and merges it into globals.base
const std = @import("std");
const strata = @import("../db/strata.zig");
const runner = @import("../build/run.zig");
const globals = @import("../globals.zig");
const db = @import("../db/db.zig");
const log = @import("../utils/log.zig");
const utils = @import("../utils/utils.zig");
const config = @import("../config.zig");
const stratum = @import("../stratum/stratum.zig");

// wrapper
fn createdir(io: std.Io, path: []const u8) !void {
    return utils.fs.createdir(io, path);
}

// strips an entire tree, will make optional at some point
fn strip_tree(io: std.Io, allocator: std.mem.Allocator, destdir: []const u8, paths: []const []const u8) !void {
    for (paths) |rel| {
        const fullpath = try std.fs.path.join(allocator, &.{ destdir, rel });
        defer allocator.free(fullpath);

        var child = std.process.spawn(io, .{
            .argv = &.{ "strip", "-S", fullpath },
            .stdout = .ignore,
            .stderr = .ignore,
        }) catch continue;

        _ = child.wait(io) catch {};
    }
}
// just changes destdir perms
fn destdir_chown(io: std.Io, path: []const u8) !void {
    log.debug1("changing ownership of staging directory: {s}\n", .{path});

    var child = try std.process.spawn(io, .{
        .argv = &.{ "chown", "-R", config.current.build_usr, path },
        .stdout = .ignore,
        .stderr = .inherit,
    });

    switch (try child.wait(io)) {
        .exited => |code| {
            if (code != 0) {
                log.err("failed to chown {s} to xpk (exit {d})\n", .{path, code});
                return error.chownfailed;
            }
            log.debug1("ownership updated: {s}\n", .{path});
        },
        else => {
            log.err("chown process terminated unexpectedly\n", .{});
            return error.chownfailed;
        },
    }
}
// stages, need sto know destdir and buildysy
pub fn stage_i(io: std.Io, allocator: std.mem.Allocator, sourced: []const u8, destdir: []const u8, buildsys: []const u8) !void {
    log.trace("staging package install using {s}\n", .{buildsys});
    try createdir(io, destdir);
    try destdir_chown(io, destdir);

    var argv: std.ArrayList([]const u8) = .empty;
    defer argv.deinit(allocator);

    if (std.mem.eql(u8, buildsys, "meson")) {
        try argv.appendSlice(allocator, &.{"meson", "install", "-C", "build"});
        const arg = try std.fmt.allocPrint(allocator, "--destdir={s}", .{destdir});
        try argv.append(allocator, arg);
    } else {
        try argv.appendSlice(allocator, &.{"make", "install"});
        const arg = try std.fmt.allocPrint(allocator, "DESTDIR={s}", .{destdir});
        try argv.append(allocator, arg);
    }

    log.debug3("running install command in {s}\n", .{sourced});
    try runner.run_step(io, allocator, argv.items, sourced);
    log.debug2("package staged successfuly\n", .{});
}
// walks and symlinks shit
pub fn walk_s(io: std.Io, allocator: std.mem.Allocator, destdir: []const u8) ![][]const u8 {
    log.trace("walking staging directory: {s}\n", .{destdir});
    var paths: std.ArrayList([]const u8) = .empty;
    errdefer {
        for (paths.items) |p| allocator.free(p);
        paths.deinit(allocator);
    }

    var dir = try std.Io.Dir.openDirAbsolute(io, destdir, .{ .iterate = true });
    defer dir.close(io);

    var walker = try dir.walk(allocator);
    defer walker.deinit();

    while (try walker.next(io)) |entry| {
        if (entry.kind != .file and entry.kind != .sym_link) continue;
        try paths.append(allocator, try allocator.dupe(u8, entry.path));
    }

    log.trace("found {d} staged files\n", .{paths.items.len});
    return paths.toOwnedSlice(allocator);
}

// strips the usr/local/ staging prefix if present
fn crel_of(rel: []const u8) []const u8 {
    return if (std.mem.startsWith(u8, rel, "usr/local/"))
        rel["usr/local/".len..]
    else
        rel;
}
// build tree entry per installed file
fn build_treeentries(io: std.Io, allocator: std.mem.Allocator, destdir: []const u8, paths: []const []const u8) ![]strata.Treeentry {
    const entries = try allocator.alloc(strata.Treeentry, paths.len);
    errdefer allocator.free(entries);

    for (paths, 0..) |rel, i| {
        const srcpath = try std.fs.path.join(allocator, &.{ destdir, rel });
        defer allocator.free(srcpath);

        const file = try std.Io.Dir.openFileAbsolute(io, srcpath, .{ .mode = .read_only });
        const st = try file.stat(io);
        file.close(io);
        const mode = st.permissions.toMode() & 0o777;

        const hash = try strata.store_content(io, allocator, srcpath, mode);

        entries[i] = .{
            .crel = crel_of(rel),
            .hash = hash,
            .mode = mode,
        };
    }

    return entries;
}
// actually installs everything
pub fn install(io: std.Io, allocator: std.mem.Allocator, sourced: []const u8, reponame: []const u8, pkgname: []const u8, category: []const u8, version: []const u8, xhash: [32]u8, buildsys: []const u8) !void {
    log.trace("install stage\n", .{});

    const destdir = try std.fmt.allocPrint(
        allocator,
        "{s}/destdir-{s}",
        .{ globals.tmp, pkgname },
    );
    defer allocator.free(destdir);

    try stage_i(io, allocator, sourced, destdir, buildsys);

    const paths = try walk_s(io, allocator, destdir);
    defer {
        for (paths) |p| allocator.free(p);
        allocator.free(paths);
    }

    if (paths.len == 0) {
        log.err("{s}'s install staged zero files, something's probably wrong with the build, check /tmp/xpk\n", .{pkgname});
        return error.emptyinstall;
    }

    log.debug1("stripping debug symbols from staged binaries\n", .{});
    try strip_tree(io, allocator, destdir, paths);

    log.trace("storing {d} files in content store\n", .{paths.len});
    const treeentries = try build_treeentries(io, allocator, destdir, paths);
    defer allocator.free(treeentries);

    log.debug1("committing tree object\n", .{});
    const treehash = try strata.commit_tree(io, allocator, treeentries);

    if (!config.current.keep_stage) {
        try strata.cleanup_stage(io, destdir);
    }
    // added some shit here, basically logic for generations, ability to make stratums, and and activation shit
    const existing = try db.read_w(io, allocator, reponame);
    defer allocator.free(existing);
    const nextgen = if (db.latest_gen(existing, pkgname)) |g| g + 1 else 0;

    // materliaze gen drops a hash marker into the generation dir
    log.debug2("materializing generation {d} for {s}\n", .{ nextgen, pkgname });
    const gendir = try strata.materialize_genh(io, allocator, reponame, pkgname, nextgen, treehash, treeentries);
    defer allocator.free(gendir);

    log.debug2("activating generation {d}\n", .{nextgen});
    try strata.activate_generation(io, allocator, reponame, pkgname, gendir);

    log.debug2("merging into {s}\n", .{globals.base});
    try strata.merge_tree(io, allocator, reponame, pkgname, treeentries);
       

    const timestamp = std.Io.Timestamp.now(io, .real);

    log.debug3("recording db entry\n", .{});
    try db.record_i(io, allocator, .{
        .name = pkgname,
        .category = category,
        .version = version,
        .repo = reponame,
        .xhash = xhash,
        .objhash = treehash,
        .installedt = timestamp.toSeconds(),
        .generation = 0,
    });

    log.debug2("sealing stratum\n", .{});
    try stratum.seal_stratum(io, allocator, pkgname, .install);
}