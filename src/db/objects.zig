//! the idea is sort of taken from nix.
//! but it goes along with our design VERY. VERY. well, so i want to use it
const std = @import("std");
const globals = @import("../globals.zig");
const log = @import("../utils/log.zig");
const utils = @import("../utils/utils.zig");
const tree = @import("types/tree.zig");

pub const Treeentry = tree.Treeentry;

fn createdir(io: std.Io, path: []const u8) !void {
    return utils.fs.createdir(io, path);
}

fn splitpath(allocator: std.mem.Allocator, roots: []const u8, hash: [32]u8) ![]u8 {
    const hex = std.fmt.bytesToHex(hash, .lower);
    return std.fs.path.join(allocator, &.{ roots, hex[0..2], hex[2..] });
}

fn content_root(allocator: std.mem.Allocator) ![]u8 {
    return std.fs.path.join(allocator, &.{ globals.objects, "content" });
}

fn trees_root(allocator: std.mem.Allocator) ![]u8 {
    return std.fs.path.join(allocator, &.{ globals.objects, "trees" });
}

pub fn content_path(allocator: std.mem.Allocator, hash: [32]u8) ![]u8 {
    const root = try content_root(allocator);
    defer allocator.free(root);
    return splitpath(allocator, root, hash);
}

pub fn tree_path(allocator: std.mem.Allocator, hash: [32]u8) ![]u8 {
    const root = try trees_root(allocator);
    defer allocator.free(root);
    return splitpath(allocator, root, hash);
}

// hashes file, simple as shit bro
pub fn hash_file(io: std.Io, path: []const u8) ![32]u8 {
    const file = try std.Io.Dir.openFileAbsolute(io, path, .{ .mode = .read_only });
    defer file.close(io);

    var hasher = std.crypto.hash.sha2.Sha256.init(.{});

    var readbuf: [64 * 1024]u8 = undefined;
    var freader = file.reader(io, &readbuf);
    const reader = &freader.interface;

    var buf: [64 * 1024]u8 = undefined;
    while (true) {
        const n = try reader.readSliceShort(&buf);
        if (n == 0) break;
        hasher.update(buf[0..n]);
    }

    var digest: [32]u8 = undefined;
    hasher.final(&digest);
    return digest;
}

// writes bytes to dest automatically, atomically so we dont lose shit
fn write_atomic(io: std.Io, allocator: std.mem.Allocator, destpath: []const u8, srcfile: std.Io.File, mode: std.posix.mode_t) !void {
    if (std.fs.path.dirname(destpath)) |parent| {
        std.Io.Dir.cwd().createDirPath(io, parent) catch |err| switch (err) {
            error.PathAlreadyExists => {},
            else => return err,
        };
    }
    // the suffix is mostly for decor
    const tmppath = try std.fmt.allocPrint(allocator, "{s}.tmp-{d}", .{ destpath, std.Io.Timestamp.now(io, .real).toSeconds() });
    defer allocator.free(tmppath);

    
    {
        const dst = try std.Io.Dir.createFileAbsolute(io, tmppath, .{ .truncate = true });
        defer dst.close(io);

        var writerbuf: [64 * 1024]u8 = undefined;
        var fwriter = dst.writer(io, &writerbuf);
        const writer = &fwriter.interface;

        var readerbuf: [64 * 1024]u8 = undefined;
        var freader = srcfile.reader(io, &readerbuf);
        const reader = &freader.interface;

        var buf: [64 * 1024]u8 = undefined;
        while (true) {
            const n = try reader.readSliceShort(&buf);
            if (n == 0) break;
            try writer.writeAll(buf[0..n]);
        }
        try writer.flush();

        // set mode BEFORE rename, so the file never exists at a discoverable path,  
        try dst.setPermissions(io, std.Io.File.Permissions.fromMode(mode));
    }

    // renaming and cross device handling in future for linux
    std.Io.Dir.renameAbsolute(tmppath, destpath, io) catch |err| switch (err) {
        error.CrossDevice => {
            const src = try std.Io.Dir.openFileAbsolute(io, tmppath, .{ .mode = .read_only });
            defer src.close(io);
            const dst = try std.Io.Dir.createFileAbsolute(io, destpath, .{ .truncate = true });
            defer dst.close(io);

            var writerbuf: [64 * 1024]u8 = undefined;
            var fwriter = dst.writer(io, &writerbuf);
            var readerbuf: [64 * 1024]u8 = undefined;
            var freader = src.reader(io, &readerbuf);
            var buf: [64 * 1024]u8 = undefined;
            while (true) {
                const n = try freader.interface.readSliceShort(&buf);
                if (n == 0) break;
                try fwriter.interface.writeAll(buf[0..n]);
            }
            try fwriter.interface.flush();
            try dst.setPermissions(io, std.Io.File.Permissions.fromMode(mode));
            std.Io.Dir.deleteFileAbsolute(io, tmppath) catch {};
        },
        else => return err,
    };
}
// stores content hash
pub fn store_content(io: std.Io,allocator: std.mem.Allocator,srcpath: []const u8, mode: std.posix.mode_t) ![32]u8 {
    const hash = try hash_file(io, srcpath);

    const dest = try content_path(allocator, hash);
    defer allocator.free(dest);

    if (std.Io.Dir.openFileAbsolute(io, dest, .{ .mode = .read_only })) |f| {
        const st = try f.stat(io);
        const existingmode = st.permissions.toMode() & 0o777;
        f.close(io);

        const wanted: std.posix.mode_t = existingmode | mode;
        if (wanted != existingmode) {
            const rw = try std.Io.Dir.openFileAbsolute(io, dest, .{ .mode = .read_write });
            defer rw.close(io);

            try rw.setPermissions(
                io,
                std.Io.File.Permissions.fromMode(wanted),
            );

            log.debug2("widened permissions on shared object {o} -> {o}\n", .{ existingmode, wanted });
        }

        return hash;
    } else |err| if (err != error.FileNotFound) return err;

    const src = try std.Io.Dir.openFileAbsolute(io, srcpath, .{ .mode = .read_only });
    defer src.close(io);

    try write_atomic(io, allocator, dest, src, mode);
    return hash;
}
// actually commits the tree
pub fn commit_tree(io: std.Io, allocator: std.mem.Allocator, entries: []Treeentry) ![32]u8 {
    tree.sort_entries(entries);

    const blob = try tree.encode_tree(allocator, entries);
    defer allocator.free(blob);

    const hash = tree.hash_tree(blob);

    const dest = try tree_path(allocator, hash);
    defer allocator.free(dest);

    if (std.Io.Dir.openFileAbsolute(io, dest, .{ .mode = .read_only })) |f| {
        f.close(io);
        return hash;
    } else |err| if (err != error.FileNotFound) return err;

    if (std.fs.path.dirname(dest)) |parent| {
        std.Io.Dir.cwd().createDirPath(io, parent) catch |err| switch (err) {
            error.PathAlreadyExists => {},
            else => return err,
        };
    }

    const file = try std.Io.Dir.createFileAbsolute(io, dest, .{ .truncate = true });
    defer file.close(io);

    var writerbuf: [16 * 1024]u8 = undefined;
    var fwriter = file.writer(io, &writerbuf);
    try fwriter.interface.writeAll(blob);
    try fwriter.interface.flush();

    return hash;
}
// loadedtree is just when we LOAD the tree rightttt surprise
pub const Loadedtree = struct {
    bytes: []const u8,
    entries: []Treeentry,

    pub fn deinit(self: *Loadedtree, allocator: std.mem.Allocator) void {
        allocator.free(self.entries);
        allocator.free(self.bytes);
    }
};

// loads tree with entries , needs to be defered 
pub fn load_tree(io: std.Io, allocator: std.mem.Allocator, hash: [32]u8) !Loadedtree {
    const path = try tree_path(allocator, hash);
    defer allocator.free(path);

    const bytes = try std.Io.Dir.cwd().readFileAlloc(io, path, allocator, .unlimited);
    errdefer allocator.free(bytes);

    const entries = try tree.decode_tree(bytes, allocator);

    return .{ .bytes = bytes, .entries = entries };
}
// links /opt/xpk/bin/(binary) to /opt/xpk/objects/(a4 <- first 2 letters, so each directory can store roughly 3096 binaries)/(rest of the 30 bytes of the hash) and so on, its pretty much identical to what OStree does under the bottom
pub fn link_tree(io: std.Io, allocator: std.mem.Allocator, entries: []const Treeentry) !void {
    for (entries) |e| {
        const target = try content_path(allocator, e.hash);
        defer allocator.free(target);

        const linkpath = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ globals.base, e.crel });
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

        log.debug2("linked {s} -> {s}\n", .{ linkpath, target });
    }
}
// deletes a tree absolute path, helper cuz i use it like thrice
fn delete_tabs(io: std.Io, abspath: []const u8) !void {
    const parent = std.fs.path.dirname(abspath) orelse return error.badpath;
    const base = std.fs.path.basename(abspath);

    var dir = try std.Io.Dir.openDirAbsolute(io, parent, .{});
    defer dir.close(io);

    try dir.deleteTree(io, base);
}
// in a function so if cleanup_stage fails the whole build doesnt fail, only function returns negative, but i could've actually just catch (err)
pub fn cleanup_stage(io: std.Io, destdir: []const u8) !void {
    try delete_tabs(io, destdir);
}