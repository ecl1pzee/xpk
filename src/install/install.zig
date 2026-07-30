const std = @import("std");
const types = @import("types/types.zig");
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

// only made to chown for destdir, thats it

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

// staged install, appends the shit, needs to know buildsys and will support more future
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

// walks stage dir recursively
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

// strips the usr/local/ staging prefix if present, same rule the old commit_i used to apply inline
fn crel_of(rel: []const u8) []const u8 {
    return if (std.mem.startsWith(u8, rel, "usr/local/"))
        rel["usr/local/".len..]
    else
        rel;
}

// builds srcrel/crel pairs from raw staged paths, used for hashing + committing to the store
fn build_pairs(allocator: std.mem.Allocator, paths: []const []const u8) ![]objects.Pathpair {
    const pairs = try allocator.alloc(objects.Pathpair, paths.len);
    errdefer allocator.free(pairs);

    for (paths, 0..) |rel, i| {
        pairs[i] = .{ .srcrel = rel, .crel = crel_of(rel) };
    }

    return pairs;
}

// writes the manifest so removal knows exactly what to delete later
pub fn write_m(io: std.Io, allocator: std.mem.Allocator, reponame: []const u8, pkgname: []const u8, paths: []const []const u8) !void {
    const cdir = try std.fs.path.join(allocator, &.{ globals.db, reponame});
    defer allocator.free(cdir);
    try createdir(io, cdir);

    const filesdir = try std.fs.path.join(allocator, &.{ globals.db, reponame, "files"});
    defer allocator.free(filesdir);
    try createdir(io, filesdir);

    const manifestpath = try std.fs.path.join(allocator, &.{ filesdir, pkgname });
    defer allocator.free(manifestpath);

    const encoded = try types.encode_m(allocator, paths);
    defer allocator.free(encoded);

    const file = try std.Io.Dir.createFileAbsolute(io, manifestpath, .{ .truncate = true });
    defer file.close(io);

    var writerbuf: [16 * 1024]u8 = undefined;
    var fwriter = file.writer(io, &writerbuf);
    try fwriter.interface.writeAll(encoded);
    try fwriter.interface.flush();

    log.trace("manifest written\n", .{});
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

    const pairs = try build_pairs(allocator, paths);
    defer allocator.free(pairs);

    log.trace("hashing staged tree\n", .{});
    const objhash = try objects.hash_t(io, allocator, destdir, pairs);

    log.debug1("committing to object store\n", .{});
    const objdir = try objects.commit_o(io, allocator, destdir, pairs, pkgname, version, objhash, config.current.keep_stage);
    defer allocator.free(objdir);

    // crel only listing after that
    const crelpaths = try allocator.alloc([]const u8, pairs.len);
    defer allocator.free(crelpaths);
    for (pairs, 0..) |pair, i| crelpaths[i] = pair.crel;

    log.debug1("linking into {s}\n", .{globals.base});
    try objects.link_o(io, allocator, objdir, crelpaths);

    // write the file manifest
    try write_m(io, allocator, reponame, pkgname, crelpaths);

    const timestamp = std.Io.Timestamp.now(io, .real);

    // write entry in database per repo, generation gets assigned by record_i itself, so we pass 0 to gen
    log.debug3("recording db entry\n", .{});
    try db.record_i(io, allocator, .{
        .name = pkgname,
        .category = category,
        .version = version,
        .repo = reponame,
        .xhash = xhash,
        .objhash = objhash,
        .installedt = timestamp.toSeconds(),
        .generation = 0, // record_i overwrites this later
    });
}