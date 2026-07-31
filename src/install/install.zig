const std = @import("std");
const objects = @import("../db/objects.zig");
const runner = @import("../build/run.zig");
const globals = @import("../globals.zig");
const db = @import("../db/db.zig");
const log = @import("../utils/log.zig");
const utils = @import("../utils/utils.zig");
const config = @import("../config.zig");


fn createdir(io: std.Io, path: []const u8) !void {
    return utils.fs.createdir(io, path);
}

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
fn build_tree_entries(io: std.Io, allocator: std.mem.Allocator, destdir: []const u8, paths: []const []const u8) ![]objects.Treeentry {
    const entries = try allocator.alloc(objects.Treeentry, paths.len);
    errdefer allocator.free(entries);

    for (paths, 0..) |rel, i| {
        const srcpath = try std.fs.path.join(allocator, &.{ destdir, rel });
        defer allocator.free(srcpath);

        const file = try std.Io.Dir.openFileAbsolute(io, srcpath, .{ .mode = .read_only });
        const st = try file.stat(io);
        file.close(io);
        const mode = st.permissions.toMode() & 0o777;

        const hash = try objects.store_content(io, allocator, srcpath, mode);

        entries[i] = .{
            .crel = crel_of(rel),
            .hash = hash,
            .mode = mode,
        };
    }

    return entries;
}

// the actual thing that installs
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
    const treeentries = try build_tree_entries(io, allocator, destdir, paths);
    defer allocator.free(treeentries);

    log.debug1("committing tree object\n", .{});
    const treehash = try objects.commit_tree(io, allocator, treeentries);

    if (!config.current.keep_stage) {
        try objects.cleanup_stage(io, destdir);
    }

    log.debug1("linking into {s}\n", .{globals.base});
    try objects.link_tree(io, allocator, treeentries);

    const timestamp = std.Io.Timestamp.now(io, .real);

    log.debug3("recording db entry\n", .{});
    try db.record_i(io, allocator, .{
        .name = pkgname,
        .category = category,
        .version = version,
        .repo = reponame,
        .xhash = xhash,
        .objhash = treehash, // tree object hash
        .installedt = timestamp.toSeconds(),
        .generation = 0, // record_i overwrites this
    });
}