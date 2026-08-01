//! the idea is sort of taken from nix.
//! but it goes along with our design VERY. VERY. well, so i want to use it
const std = @import("std");
const globals = @import("../globals.zig");
const log = @import("../utils/log.zig");
const utils = @import("../utils/utils.zig");
const tree = @import("types/tree.zig");

pub const Treeentry = tree.Treeentry;

pub const treehashm = ".xpk-treehash";

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

fn write_atomic(io: std.Io, allocator: std.mem.Allocator, destpath: []const u8, srcfile: std.Io.File, mode: std.posix.mode_t) !void {
    if (std.fs.path.dirname(destpath)) |parent| {
        std.Io.Dir.cwd().createDirPath(io, parent) catch |err| switch (err) {
            error.PathAlreadyExists => {},
            else => return err,
        };
    }
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

        try dst.setPermissions(io, std.Io.File.Permissions.fromMode(mode));
    }
    // i would just use rename, but ours requires mode so i just copy paste in contents and add mode
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

pub fn store_content(io: std.Io, allocator: std.mem.Allocator, srcpath: []const u8, mode: std.posix.mode_t) ![32]u8 {
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

pub const Loadedtree = struct {
    bytes: []const u8,
    entries: []Treeentry,

    pub fn deinit(self: *Loadedtree, allocator: std.mem.Allocator) void {
        allocator.free(self.entries);
        allocator.free(self.bytes);
    }
};

pub fn load_tree(io: std.Io, allocator: std.mem.Allocator, hash: [32]u8) !Loadedtree {
    const path = try tree_path(allocator, hash);
    defer allocator.free(path);

    const bytes = try std.Io.Dir.cwd().readFileAlloc(io, path, allocator, .unlimited);
    errdefer allocator.free(bytes);

    const entries = try tree.decode_tree(bytes, allocator);

    return .{ .bytes = bytes, .entries = entries };
}

pub fn generation_path(allocator: std.mem.Allocator, reponame: []const u8, pkgname: []const u8, generation: u32) ![]u8 {
    var genbuf: [10]u8 = undefined;
    const genstr = try std.fmt.bufPrint(&genbuf, "layer-{d}", .{generation});
    return std.fs.path.join(allocator, &.{ globals.strata, reponame, pkgname, genstr });
}

pub fn current_path(allocator: std.mem.Allocator, reponame: []const u8, pkgname: []const u8) ![]u8 {
    return std.fs.path.join(allocator, &.{ globals.current, reponame, pkgname });
}

fn write_treehashm(io: std.Io, allocator: std.mem.Allocator, gendir: []const u8, hash: [32]u8) !void {
    const markerpath = try std.fs.path.join(allocator, &.{ gendir, treehashm });
    defer allocator.free(markerpath);

    const hex = std.fmt.bytesToHex(hash, .lower);

    const file = try std.Io.Dir.createFileAbsolute(io, markerpath, .{ .truncate = true });
    defer file.close(io);

    var writerbuf: [80]u8 = undefined;
    var fwriter = file.writer(io, &writerbuf);
    try fwriter.interface.writeAll(&hex);
    try fwriter.interface.flush();
}

pub fn materialize_generation(io: std.Io, allocator: std.mem.Allocator, reponame: []const u8, pkgname: []const u8, generation: u32, entries: []const Treeentry) ![]u8 {
    const gendir = try generation_path(allocator, reponame, pkgname, generation);
    errdefer allocator.free(gendir);

    try createdir(io, gendir);

    for (entries) |e| {
        const target = try content_path(allocator, e.hash);
        defer allocator.free(target);

        const linkpath = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ gendir, e.crel });
        defer allocator.free(linkpath);

        if (std.fs.path.dirname(linkpath)) |parent| {
            std.Io.Dir.cwd().createDirPath(io, parent) catch |err| switch (err) {
                error.PathAlreadyExists => {},
                else => return err,
            };
        }

        try std.Io.Dir.symLinkAbsolute(io, target, linkpath, .{});

        log.debug2("materialized {s} -> {s}\n", .{ linkpath, target });
    }

    return gendir;
}


pub fn materialize_genh(io: std.Io, allocator: std.mem.Allocator, reponame: []const u8, pkgname: []const u8, generation: u32, treehash: [32]u8, entries: []const Treeentry) ![]u8 {
    const gendir = try materialize_generation(io, allocator, reponame, pkgname, generation, entries); // gender 
    errdefer allocator.free(gendir);

    try write_treehashm(io, allocator, gendir, treehash);

    return gendir;
}

pub fn activate_generation(io: std.Io, allocator: std.mem.Allocator, reponame: []const u8, pkgname: []const u8, gendir: []const u8) !void {
    const currentdir = try std.fs.path.join(allocator, &.{ globals.current, reponame });
    defer allocator.free(currentdir);
    try createdir(io, currentdir);

    const linkpath = try current_path(allocator, reponame, pkgname);
    defer allocator.free(linkpath);

    const tmppath = try std.fmt.allocPrint(allocator, "{s}.tmp-{d}", .{ linkpath, std.Io.Timestamp.now(io, .real).toSeconds() });
    defer allocator.free(tmppath);

    std.Io.Dir.deleteFileAbsolute(io, tmppath) catch |err| switch (err) {
        error.FileNotFound => {},
        else => return err,
    };

    try std.Io.Dir.symLinkAbsolute(io, gendir, tmppath, .{});

    std.Io.Dir.renameAbsolute(tmppath, linkpath, io) catch |err| switch (err) {
        error.CrossDevice => {
            std.Io.Dir.deleteFileAbsolute(io, linkpath) catch |derr| switch (derr) {
                error.FileNotFound => {},
                else => return derr,
            };
            try std.Io.Dir.symLinkAbsolute(io, gendir, linkpath, .{});
            std.Io.Dir.deleteFileAbsolute(io, tmppath) catch {};
        },
        else => return err,
    };

    log.debug1("activated {s}/{s} -> {s}\n", .{ reponame, pkgname, gendir });
}


pub fn merge_tree(io: std.Io, allocator: std.mem.Allocator, entries: []const Treeentry) !void {
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

fn delete_tabs(io: std.Io, abspath: []const u8) !void {
    const parent = std.fs.path.dirname(abspath) orelse return error.badpath;
    const base = std.fs.path.basename(abspath);

    var dir = try std.Io.Dir.openDirAbsolute(io, parent, .{});
    defer dir.close(io);

    try dir.deleteTree(io, base);
}

pub fn remove_generation(io: std.Io, gendir: []const u8) !void {
    try delete_tabs(io, gendir);
}

pub fn cleanup_stage(io: std.Io, destdir: []const u8) !void {
    try delete_tabs(io, destdir);
}