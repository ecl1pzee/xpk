const std = @import("std");
const types = @import("types/types.zig");
const runner = @import("../build/run.zig");
const globals = @import("../globals.zig");
const db = @import("../db/db.zig");
const print = std.debug.print;

inline fn wprint(comptime fmt: []const u8, args: anytype) void {
    print("[!] " ++ fmt, args);
}
inline fn iprint(comptime fmt: []const u8, args: anytype) void {
    print("[*] " ++ fmt, args);
}

fn createdir(io: std.Io, path: []const u8) !void {
    std.Io.Dir.createDirAbsolute(io, path, .default_dir) catch |err| switch (err) {
        error.PathAlreadyExists => {},
        else => return err,
    };
}
// only made to chown for destdir, thats it
fn destdir_chown(io: std.Io, path: []const u8) !void {
    var child = try std.process.spawn(io, .{
        .argv = &.{ "chown", "-R", "xpk", path },
        .stdout = .ignore,
        .stderr = .inherit,
    });


    switch (try child.wait(io)) {
        .exited => |code| {
            if (code != 0) {
                wprint("failed to chown {s} to xpk\n", .{path});
                return error.chownfailed;
            }
        },
        else => return error.chownfailed,
    }
}

// staged install, appends the shit, needs to know buildsys and will support more future
pub fn stage_i(io: std.Io, allocator: std.mem.Allocator, sourced: []const u8, destdir: []const u8, buildsys: []const u8) !void {
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

    try runner.run_step(io, allocator, argv.items, sourced);
}

// walks stage dir recursively
pub fn walk_s(io: std.Io, allocator: std.mem.Allocator, destdir: []const u8) ![][]const u8 {
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

    return paths.toOwnedSlice(allocator);
}

// copies the shit
pub fn commit_i(io: std.Io, allocator: std.mem.Allocator, destdir: []const u8, paths: []const []const u8) ![][]const u8 {
    var installedp: std.ArrayList([]const u8) = .empty;
    errdefer {
        for (installedp.items) |p| allocator.free(p);
        installedp.deinit(allocator);
    }

    const root = try std.Io.Dir.openDirAbsolute(io, globals.base ++ "/", .{});
    defer root.close(io);

    for (paths) |rel| {
        const srcpath = try std.fs.path.join(allocator, &.{ destdir, rel });
        defer allocator.free(srcpath);

        // if path is usr local, thenwe fucking remove that
        const crel = if (std.mem.startsWith(u8, rel, "usr/local/"))
            rel["usr/local/".len..]
        else
            rel;

    
        try installedp.append(allocator, try allocator.dupe(u8, crel));

        const dstpath = try std.fmt.allocPrint(
            allocator,
            "{s}/{s}",
            .{ globals.base, crel },
        );
        defer allocator.free(dstpath);

        if (std.fs.path.dirname(dstpath)) |parent| {
            root.createDirPath(io, parent) catch |err| switch (err) {
                error.PathAlreadyExists => {},
                else => return err,
            };
        }

        const src = try std.Io.Dir.openFileAbsolute(io, srcpath, .{ .mode = .read_only });
        defer src.close(io);

        const dst = try std.Io.Dir.createFileAbsolute(io, dstpath, .{ .truncate = true });
        defer dst.close(io);

        var writerbuf: [64 * 1024]u8 = undefined;
        var fwriter = dst.writer(io, &writerbuf);
        const writer = &fwriter.interface;

        var readerbuf: [64 * 1024]u8 = undefined;
        var freader = src.reader(io, &readerbuf);
        const reader = &freader.interface;

        var buf: [64 * 1024]u8 = undefined;

        while (true) {
            const n = try reader.readSliceShort(&buf);
            if (n == 0) break;
            try writer.writeAll(buf[0..n]);
        }

        try writer.flush();

        const st = try src.stat(io);
        try dst.setPermissions(io, st.permissions);
    }

    return installedp.toOwnedSlice(allocator);
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
}

// the actual thing that installs
pub fn install(io: std.Io, allocator: std.mem.Allocator, sourced: []const u8, reponame: []const u8, pkgname: []const u8, category: []const u8, version: []const u8, xhash: [32]u8, buildsys: []const u8) !void {
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
        wprint("{s}'s install staged zero files, something's probably wrong with the build, check /tmp/xpk\n", .{pkgname});
        return error.emptyinstall;
    }

    const installedp = try commit_i(io, allocator, destdir, paths);
    defer {
        for (installedp) |p| {
            allocator.free(p);
        }
        allocator.free(installedp);
    }

    // write the file manifest
    try write_m(io, allocator, reponame, pkgname, installedp);

    const timestamp = std.Io.Timestamp.now(io, .real);

    // write entry in database per repo, for sortinf ofc
    try db.record_i(io, allocator, .{.name = pkgname,.category = category, .version = version, .repo = reponame, .xhash = xhash, .installedt = timestamp.toSeconds()});
}