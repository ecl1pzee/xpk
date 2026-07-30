//! the idea is sort of taken from nix.
//! but it goes along with our design VERY. VERY. well, so i want to use it
//! layout: /opt/xpk/objects/name-version-(objhash)/<staged tree, usr/local stripped>
const std = @import("std");
const globals = @import("../globals.zig");
const log = @import("../utils/log.zig");
const utils = @import("../utils/utils.zig");


fn createdir(io: std.Io, path: []const u8) !void {
    return utils.fs.createdir(io, path);
}


// deletes tree, but absolute, also a helper i made because for some fucking reason std.Io.Dir only has deletetree 
fn delete_tabs(io: std.Io, abspath: []const u8) !void {
    const parent = std.fs.path.dirname(abspath) orelse return error.badpath;
    const base = std.fs.path.basename(abspath);

    var dir = try std.Io.Dir.openDirAbsolute(io, parent, .{});
    defer dir.close(io);

    try dir.deleteTree(io, base);
}

pub const Pathpair = struct {
    srcrel: []const u8, 
    crel: []const u8,  
};

// special hash, specifically for the object directories
pub fn hash_t(io: std.Io, allocator: std.mem.Allocator, destdir: []const u8, pairs: []const Pathpair) ![32]u8 {
    const sorted = try allocator.dupe(Pathpair, pairs);
    defer allocator.free(sorted);
    std.mem.sort(Pathpair, sorted, {}, struct {
        fn lessThan(_: void, a: Pathpair, b: Pathpair) bool {
            return std.mem.order(u8, a.crel, b.crel) == .lt;
        }
    }.lessThan);

    var hasher = std.crypto.hash.sha2.Sha256.init(.{});

    for (sorted) |pair| {
        hasher.update(pair.crel);

        const srcpath = try std.fs.path.join(allocator, &.{ destdir, pair.srcrel });
        defer allocator.free(srcpath);

        const file = try std.Io.Dir.openFileAbsolute(io, srcpath, .{ .mode = .read_only });
        defer file.close(io);

        const st = try file.stat(io);
        const mode = st.permissions.toMode() & 0o777;
        var modebuf: [4]u8 = undefined;
        std.mem.writeInt(u32, &modebuf, mode, .little);
        hasher.update(&modebuf);

        var readbuf: [64 * 1024]u8 = undefined;
        var freader = file.reader(io, &readbuf);
        const reader = &freader.interface;

        var buf: [64 * 1024]u8 = undefined;
        while (true) {
            const n = try reader.readSliceShort(&buf);
            if (n == 0) break;
            hasher.update(buf[0..n]);
        }
    }

    var digest: [32]u8 = undefined;
    hasher.final(&digest);
    return digest;
}

// object builder, just a neat tool, also i keep name and version first so when you ls you dont just see random bullshit
pub fn object_dirname(allocator: std.mem.Allocator, name: []const u8, version: []const u8, objhash: [32]u8) ![]u8 {
    const hex = std.fmt.bytesToHex(objhash, .lower);
    return std.fmt.allocPrint(allocator, "{s}-{s}-{s}", .{ name, version, hex });
}

// writing under crel (final) paths, dedups if the object already exists
pub fn commit_o(io: std.Io, allocator: std.mem.Allocator, destdir: []const u8, pairs: []const Pathpair, name: []const u8, version: []const u8, objhash: [32]u8, keep_stage: bool) ![]const u8 {
    try createdir(io, globals.objects);

    const dirname = try object_dirname(allocator, name, version, objhash);
    defer allocator.free(dirname);

    const objdir = try std.fs.path.join(allocator, &.{ globals.objects, dirname });
    errdefer allocator.free(objdir);

    if (std.Io.Dir.openDirAbsolute(io, objdir, .{})) |dir| {
        var d = dir;
        d.close(io);
        log.debug1("object {s} already exists, deduping\n", .{dirname});
        if (!keep_stage) try delete_tabs(io, destdir);
        return objdir;
    } else |err| if (err != error.FileNotFound) return err;

    try createdir(io, objdir);

    for (pairs) |pair| {
        const srcpath = try std.fs.path.join(allocator, &.{ destdir, pair.srcrel });
        defer allocator.free(srcpath);

        const dstpath = try std.fs.path.join(allocator, &.{ objdir, pair.crel });
        defer allocator.free(dstpath);

        if (std.fs.path.dirname(dstpath)) |parent| {
            std.Io.Dir.cwd().createDirPath(io, parent) catch |err| switch (err) {
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

    if (!keep_stage) try delete_tabs(io, destdir);

    
    return objdir;
}

// symlinks every crel path in the object dir, and yeah lets us have shit in /bin later
pub fn link_o(io: std.Io, allocator: std.mem.Allocator, objdir: []const u8, crelpaths: []const []const u8) !void {
    for (crelpaths) |crel| {
        const target = try std.fs.path.join(allocator, &.{ objdir, crel });
        defer allocator.free(target);

        const linkpath = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ globals.base, crel });
        defer allocator.free(linkpath);

        if (std.fs.path.dirname(linkpath)) |parent| {
            std.Io.Dir.cwd().createDirPath(io, parent) catch |err| switch (err) {
                error.PathAlreadyExists => {},
                else => return err,
            };
        }

        std.Io.Dir.deleteFileAbsolute(io, linkpath) catch |err| switch (err) {
            error.FileNotFound => {},
            else => return err,
        };

        try std.Io.Dir.symLinkAbsolute(io, target, linkpath, .{});
    }
}