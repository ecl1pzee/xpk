const std = @import("std");
const types = @import("types/types.zig");
const globals = @import("../globals.zig");
const utils = @import("../utils/utils.zig");
const log = @import("../utils/log.zig");

// the plan is, to have (later) a sort of pacman menu where u select from where the package comes from, and an option to void that and choose highest priority.
pub const Dbentry = types.Dbentry;


fn createdir(io: std.Io, path: []const u8) !void {
    return utils.fs.createdir(io, path);
}


fn worldpath(allocator: std.mem.Allocator, reponame: []const u8) ![]u8 {
    return std.fs.path.join(allocator, &.{ globals.db, reponame, "world" });
}

// reads a repo's world file
pub fn read_w(io: std.Io, allocator: std.mem.Allocator, reponame: []const u8) ![]Dbentry {
    const path = try worldpath(allocator, reponame);
    defer allocator.free(path);

    const bytes = std.Io.Dir.cwd().readFileAlloc(io, path, allocator, .unlimited) catch |err| switch (err) {
        error.FileNotFound => return &.{},
        else => return err,
    };
    defer allocator.free(bytes);

    return types.parse_db(bytes, allocator);
}

// writes a repo's world file, creating /opt/xpk/db/(reponame)/ if this is its first entry
pub fn write_w(io: std.Io, allocator: std.mem.Allocator, reponame: []const u8, entries: []const Dbentry) !void {
    const repodbdir = try std.fs.path.join(allocator, &.{ globals.db, reponame });
    defer allocator.free(repodbdir);
    try createdir(io, repodbdir);

    log.trace("creating new entry and encoding it\n", .{});
    const path = try worldpath(allocator, reponame);
    defer allocator.free(path);

    
    const encoded = try types.encode_db(allocator, entries);
    defer allocator.free(encoded);

    const file = try std.Io.Dir.createFileAbsolute(io, path, .{ .truncate = true });
    defer file.close(io);

    var writerbuf: [16 * 1024]u8 = undefined;
    var fwriter = file.writer(io, &writerbuf);
    try fwriter.interface.writeAll(encoded);
    try fwriter.interface.flush();
}

// finds latest gen
pub fn latest_gen(existing: []const Dbentry, name: []const u8) ?u32 {
    var best: ?u32 = null;
    for (existing) |e| {
        if (!std.mem.eql(u8, e.name, name)) continue;
        if (best == null or e.generation > best.?) best = e.generation;
    }
    return best;
}

// returns highest generation
pub fn current_e(existing: []const Dbentry, name: []const u8) ?Dbentry {
    var best: ?Dbentry = null;
    for (existing) |e| {
        if (!std.mem.eql(u8, e.name, name)) continue;
        if (best == null or e.generation > best.?.generation) best = e;
    }
    return best;
}

// record new gen on install
pub fn record_i(io: std.Io, allocator: std.mem.Allocator, entry: Dbentry) !void {
    const existing = try read_w(io, allocator, entry.repo);
    defer allocator.free(existing);

    const nextgen = if (latest_gen(existing, entry.name)) |g| g + 1 else 0;

    var list: std.ArrayList(Dbentry) = .empty;
    defer list.deinit(allocator);

    try list.appendSlice(allocator, existing);

    var stamped = entry;
    stamped.generation = nextgen;
    try list.append(allocator, stamped);

    log.trace("recording generation {d} for {s}\n", .{ nextgen, entry.name });

    try write_w(io, allocator, entry.repo, list.items);
}

// removes ALL generations 
// full removal, not a single gen prune, single gens are gonna be done w garbage collecter
pub fn remove_i(io: std.Io, allocator: std.mem.Allocator, reponame: []const u8, name: []const u8) !void {
    const existing = try read_w(io, allocator, reponame);
    defer allocator.free(existing);

    var list: std.ArrayList(Dbentry) = .empty;
    defer list.deinit(allocator);

    for (existing) |e| {
        if (!std.mem.eql(u8, e.name, name)) try list.append(allocator, e);
    }

    try write_w(io, allocator, reponame, list.items);
}

pub const Resolved = struct {
    repo: utils.parser.Repo,
    entry: types.Dbentry, // from index
};

// resolves which repo owns a package, figured i'd do this early on to avoid shit later
pub fn resolve_p(candidates: []const struct { repo: utils.parser.Repo, found: bool }) ?utils.parser.Repo {
    var best: ?utils.parser.Repo = null;

    for (candidates) |c| {
        if (!c.found) continue;
        if (best == null or c.repo.priority > best.?.priority) {
            best = c.repo;
        }
    }

    return best;
}