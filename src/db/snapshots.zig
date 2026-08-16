//! big ass rework
//! but in a nutshell, recursive trees,and a hash chain (well, it was there but greatly improved)
//! its impossible to screw with the logs now, each new log verifies each old one 
const std = @import("std");
const globals = @import("../globals.zig");
const log = @import("../utils/log.zig");
const utils = @import("../utils/utils.zig");
const tree = @import("types/tree.zig");
const owners = @import("../db/types/owners.zig");

pub const Treeentry = tree.Treeentry;
pub const Kind = tree.Kind;

pub const treehashm = ".xpk-treehash";

fn createdir(io: std.Io, path: []const u8) !void {
    return utils.fs.createdir(io, path);
}

fn splitpath(allocator: std.mem.Allocator, roots: []const u8, hash: [32]u8) ![]u8 {
    const hex = std.fmt.bytesToHex(hash, .lower);
    return std.fs.path.join(allocator, &.{ roots, hex[0..2], hex[2..] });
}
// ill keep these incase i wanna change, prob not i hope cuz it woulddd require a shit ton of work
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
// hashes a file based on path not a handle to a file
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
// writes atomically. nothing else.
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

fn write_treeobj(io: std.Io, allocator: std.mem.Allocator, entries: []Treeentry, dirmode: u32) ![32]u8 {
    tree.sort_entries(entries);

    const blob = try tree.encode_tree(allocator, entries, dirmode);
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
// one staged file
pub const Stagedfile = struct {
    crel: []const u8,
    hash: [32]u8,
    mode: u32,
};
// these nodes are way easier to work w, but its not the point:
// optimization is.
// actually, its ironic because our last method was faster since it was less convoluted. 
// but, its an architechtural change for later, since we want auditing we needed subtree skipping and avoiding rehashing per procedure
// so long term it is better 
const Dirnode = struct {
    children: std.StringHashMap(*Dirnode), // recurisve, as i already said
    files: std.ArrayList(Stagedfile),
    mode: u32 = 0o755, // default 

    fn init(allocator: std.mem.Allocator) Dirnode {
        return .{.children = std.StringHashMap(*Dirnode).init(allocator),.files = .empty};
    }

    fn deinit(self: *Dirnode, allocator: std.mem.Allocator) void {
        var it = self.children.valueIterator();
        while (it.next()) |child| {
            child.*.deinit(allocator);
            allocator.destroy(child.*);
        }
        self.children.deinit();
        self.files.deinit(allocator);
    }
};
// creates child if doesn't exist, likewise gets if exists
fn get_createchild(allocator: std.mem.Allocator, node: *Dirnode, name: []const u8) !*Dirnode {
    if (node.children.get(name)) |existing| return existing;

    const child = try allocator.create(Dirnode);
    child.* = Dirnode.init(allocator);
    try node.children.put(try allocator.dupe(u8, name), child);
    return child;
}
// inserts a file
fn insert_file(allocator: std.mem.Allocator, root: *Dirnode, crel: []const u8, hash: [32]u8, mode: u32) !void {
    var it = std.mem.splitScalar(u8, crel, '/');
    var node = root;

    var parts: std.ArrayList([]const u8) = .empty;
    defer parts.deinit(allocator);
    while (it.next()) |part| try parts.append(allocator, part);

    for (parts.items[0 .. parts.items.len - 1]) |dirname| {
        node = try get_createchild(allocator, node, dirname);
    }

    try node.files.append(allocator, .{
        .crel = parts.items[parts.items.len - 1],
        .hash = hash,
        .mode = mode,
    });
}

// recursively builds and writes
// then yeah, commits it
fn commit_node(io: std.Io, allocator: std.mem.Allocator, node: *Dirnode) ![32]u8 {
    var entries: std.ArrayList(Treeentry) = .empty;
    defer entries.deinit(allocator);

    for (node.files.items) |f| {
        try entries.append(allocator, .{
            .name = f.crel,
            .hash = f.hash,
            .mode = f.mode,
            .kind = .file,
        });
    }

    var childit = node.children.iterator();
    while (childit.next()) |entry| {
        const childhash = try commit_node(io, allocator, entry.value_ptr.*);
        try entries.append(allocator, .{
            .name = entry.key_ptr.*,
            .hash = childhash,
            .mode = entry.value_ptr.*.mode,
            .kind = .dir,
        });
    }

    return write_treeobj(io, allocator, entries.items, node.mode);
}

// builds the full recursive tree from a flat list of staged files, returns root hash
pub fn commit_tree(io: std.Io, allocator: std.mem.Allocator, files: []const Stagedfile) ![32]u8 {
    var root = Dirnode.init(allocator);
    defer root.deinit(allocator);

    for (files) |f| {
        try insert_file(allocator, &root, f.crel, f.hash, f.mode);
    }

    return commit_node(io, allocator, &root);
}

pub const Loadedtree = struct {
    bytes: []const u8,
    entries: []Treeentry,
    dirmode: u32,

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

    const decoded = try tree.decode_tree(bytes, allocator);

    return .{ .bytes = bytes, .entries = decoded.entries, .dirmode = decoded.dirmode };
}

// recursively walks a tree object graph, calling cb for every FILE leaf with its full crel path
pub fn walk_tree(io: std.Io, allocator: std.mem.Allocator, roothash: [32]u8, prefix: []const u8, cb: *const fn (allocator: std.mem.Allocator, crel: []const u8, hash: [32]u8, mode: u32, ctx: *anyopaque) anyerror!void, ctx: *anyopaque) !void {
    var loaded = try load_tree(io, allocator, roothash);
    defer loaded.deinit(allocator);

    for (loaded.entries) |e| {
        const fullpath = if (prefix.len == 0)
            try allocator.dupe(u8, e.name)
        else
            try std.fmt.allocPrint(allocator, "{s}/{s}", .{ prefix, e.name });
        defer allocator.free(fullpath);

        switch (e.kind) {
            .file => try cb(allocator, fullpath, e.hash, e.mode, ctx),
            .dir => try walk_tree(io, allocator, e.hash, fullpath, cb, ctx),
        }
    }
}

pub fn generation_path(allocator: std.mem.Allocator, reponame: []const u8, pkgname: []const u8, generation: u32) ![]u8 {
    var genbuf: [10]u8 = undefined;
    const genstr = try std.fmt.bufPrint(&genbuf, "layer-{d}", .{generation});
    return std.fs.path.join(allocator, &.{ globals.snapshots, reponame, pkgname, genstr });
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

    var writerbuf: [80]u8 = undefined; // 80 felt like it
    var fwriter = file.writer(io, &writerbuf);
    try fwriter.interface.writeAll(&hex);
    try fwriter.interface.flush();
}

const Materializectx = struct {
    io: std.Io,
    allocator: std.mem.Allocator,
    gendir: []const u8,
};
// discard mode cuz we dont use it but don't wan unused var eeror
fn materialize_cb(allocator: std.mem.Allocator, crel: []const u8, hash: [32]u8, mode: u32, ctx: *anyopaque) anyerror!void {
    _ = mode;
    const c: *Materializectx = @ptrCast(@alignCast(ctx));

    const target = try content_path(allocator, hash);
    defer allocator.free(target);

    const linkpath = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ c.gendir, crel });
    defer allocator.free(linkpath);

    if (std.fs.path.dirname(linkpath)) |parent| {
        std.Io.Dir.cwd().createDirPath(c.io, parent) catch |err| switch (err) {
            error.PathAlreadyExists => {},
            else => return err,
        };
    }

    try std.Io.Dir.symLinkAbsolute(c.io, target, linkpath, .{});

    log.debug2("materialized {s} -> {s}\n", .{ linkpath, target });
}
// smalll changes, now relies on other functions more so i deleted alot from it
pub fn materialize_generation(io: std.Io, allocator: std.mem.Allocator, reponame: []const u8, pkgname: []const u8, generation: u32, roothash: [32]u8) ![]u8 {
    const gendir = try generation_path(allocator, reponame, pkgname, generation);
    errdefer allocator.free(gendir);

    try createdir(io, gendir);

    var ctx = Materializectx{ .io = io, .allocator = allocator, .gendir = gendir };
    try walk_tree(io, allocator, roothash, "", materialize_cb, @ptrCast(&ctx));

    return gendir;
}

pub fn materialize_genh(io: std.Io, allocator: std.mem.Allocator, reponame: []const u8, pkgname: []const u8, generation: u32, treehash: [32]u8) ![]u8 {
    const gendir = try materialize_generation(io, allocator, reponame, pkgname, generation, treehash);
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

fn ownerspath(allocator: std.mem.Allocator) ![]u8 {
    return std.fs.path.join(allocator, &.{ globals.db, "owners" });
}

pub fn read_owners(io: std.Io, allocator: std.mem.Allocator) ![]owners.Ownerentry {
    const path = try ownerspath(allocator);
    defer allocator.free(path);

    const bytes = std.Io.Dir.cwd().readFileAlloc(io, path, allocator, .unlimited) catch |err| switch (err) {
        error.FileNotFound => return &.{},
        else => return err,
    };
    defer allocator.free(bytes);

    return owners.decode_owners(bytes, allocator);
}

pub fn write_owners(io: std.Io, allocator: std.mem.Allocator, entries: []const owners.Ownerentry) !void {
    const path = try ownerspath(allocator);
    defer allocator.free(path);

    const encoded = try owners.encode_owners(allocator, entries);
    defer allocator.free(encoded);

    const file = try std.Io.Dir.createFileAbsolute(io, path, .{ .truncate = true });
    defer file.close(io);

    var writerbuf: [16 * 1024]u8 = undefined;
    var fwriter = file.writer(io, &writerbuf);
    try fwriter.interface.writeAll(encoded);
    try fwriter.interface.flush();
}
// merge error, fun fact most names are actually inspired by git, except snapshots, thats a geology term. may eventually change to when settling on v1
pub const Mergeerror = error{pathownedbyanother};

const Mergectx = struct {
    io: std.Io,
    allocator: std.mem.Allocator,
    reponame: []const u8,
    pkgname: []const u8,
    existing: []const owners.Ownerentry,
    updated: *std.ArrayList(owners.Ownerentry),
};
// same thing as in remove, we must use these, so discarding is the only way
fn merge_checkcb(allocator: std.mem.Allocator, crel: []const u8, hash: [32]u8, mode: u32, ctx: *anyopaque) anyerror!void {
    _ = allocator;
    _ = hash;
    _ = mode;
    const c: *Mergectx = @ptrCast(@alignCast(ctx));

    if (owners.find_owner(c.existing, crel)) |owner| {
        if (!std.mem.eql(u8, owner.reponame, c.reponame) or !std.mem.eql(u8, owner.pkgname, c.pkgname)) {
            log.err("refusing merge: {s} is already owned by {s}/{s}, conflicts with {s}/{s}\n", .{ crel, owner.reponame, owner.pkgname, c.reponame, c.pkgname });
            return Mergeerror.pathownedbyanother;
        }
    }
}

// no need for mode = discard
// also this new update prevents faster write = more rights
fn merge_linkcb(allocator: std.mem.Allocator, crel: []const u8, hash: [32]u8, mode: u32, ctx: *anyopaque) anyerror!void {
    _ = mode;
    const c: *Mergectx = @ptrCast(@alignCast(ctx));

    // re check owner
    if (owners.find_owner(c.existing, crel)) |owner| {
        if (!std.mem.eql(u8, owner.reponame, c.reponame) or !std.mem.eql(u8, owner.pkgname, c.pkgname)) {
            log.err("refusing link: {s} is already owned by {s}/{s}, will not clobber\n", .{ crel, owner.reponame, owner.pkgname });
            return Mergeerror.pathownedbyanother;
        }
    }

    const target = try content_path(allocator, hash);
    defer allocator.free(target);

    const linkpath = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ globals.base, crel });
    defer allocator.free(linkpath);

    if (std.fs.path.dirname(linkpath)) |parent| {
        std.Io.Dir.cwd().createDirPath(c.io, parent) catch |err| switch (err) {
            error.PathAlreadyExists => {},
            else => return err,
        };
    }

    std.Io.Dir.deleteFileAbsolute(c.io, linkpath) catch |err| switch (err) {
        error.FileNotFound => {},
        else => return err,
    };

    try std.Io.Dir.symLinkAbsolute(c.io, target, linkpath, .{});

    log.debug2("linked {s} -> {s}\n", .{ linkpath, target });

    const owned = try allocator.dupe(u8, crel);
    if (owners.find_owner(c.updated.items, owned) == null) {
        try c.updated.append(allocator, .{
            .crel = owned,
            .reponame = c.reponame,
            .pkgname = c.pkgname,
        });
    }
}
// merges a tree,  main thing, is actually the orchestrator of everything.
pub fn merge_tree(io: std.Io, allocator: std.mem.Allocator, reponame: []const u8, pkgname: []const u8, roothash: [32]u8) !void {
    const existing = try read_owners(io, allocator);
    defer allocator.free(existing);

    var updated: std.ArrayList(owners.Ownerentry) = .empty;
    defer updated.deinit(allocator);
    try updated.appendSlice(allocator, existing);

    // i unrolled these now for readability
    var checkctx = Mergectx{
        .io = io,
        .allocator = allocator,
        .reponame = reponame,
        .pkgname = pkgname,
        .existing = existing,
        .updated = &updated,
    };
    try walk_tree(io, allocator, roothash, "", merge_checkcb, @ptrCast(&checkctx));

    var linkctx = Mergectx{
        .io = io,
        .allocator = allocator,
        .reponame = reponame,
        .pkgname = pkgname,
        .existing = existing,
        .updated = &updated,
    };
    try walk_tree(io, allocator, roothash, "", merge_linkcb, @ptrCast(&linkctx));

    try write_owners(io, allocator, updated.items);
}

pub fn release_ownership(io: std.Io, allocator: std.mem.Allocator, reponame: []const u8, pkgname: []const u8) !void {
    const existing = try read_owners(io, allocator);
    defer allocator.free(existing);

    var kept: std.ArrayList(owners.Ownerentry) = .empty;
    defer kept.deinit(allocator);

    for (existing) |e| {
        if (std.mem.eql(u8, e.reponame, reponame) and std.mem.eql(u8, e.pkgname, pkgname)) continue;
        try kept.append(allocator, e);
    }

    try write_owners(io, allocator, kept.items);
}

fn delete_tabs(io: std.Io, abspath: []const u8) !void {
    const parent = std.fs.path.dirname(abspath) orelse return error.badpath;
    const base = std.fs.path.basename(abspath);

    var dir = try std.Io.Dir.openDirAbsolute(io, parent, .{});
    defer dir.close(io);

    try dir.deleteTree(io, base);
}


// macros (use these a shit ton)
pub fn remove_generation(io: std.Io, gendir: []const u8) !void {
    try delete_tabs(io, gendir);
}

pub fn cleanup_stage(io: std.Io, destdir: []const u8) !void {
    try delete_tabs(io, destdir);
}