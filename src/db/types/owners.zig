//! the owners database is a binary format that tracks which package owns which paths in the filesystem, so that we can prevent two packages from claiming the same path and overwriting each other
//! yeah
const std = @import("std");

// the tenth copy paste of our binary format, dont care enough to make a generic one, its not like this is a library or anything, and bp dioesnt work good
const magic = "XPKO";
const formatvers: u16 = 1;

pub const Ownerentry = struct {
    crel: []const u8,
    reponame: []const u8,
    pkgname: []const u8,
};

pub const Ownererror = error{ badmagic, unsupportedvers, crcmismatch, truncated };

fn write_f(list: *std.ArrayList(u8), allocator: std.mem.Allocator, field: []const u8) !void {
    var lenbuf: [2]u8 = undefined;

    std.mem.writeInt(u16,&lenbuf,@intCast(field.len),.little);

    try list.appendSlice(allocator, &lenbuf);

    // had memcpy issues here, overlapping shit so i decided to dupe because memcpy doesn't allowz zero copy slices
    const copy = try allocator.dupe(u8, field);
    defer allocator.free(copy);

    try list.appendSlice(allocator, copy);
}


// fix
fn read_f(buf: []const u8, pos: *usize) []const u8 {
    const len = std.mem.readInt(u16, buf[pos.*..][0..2], .little);
    pos.* += 2;
    const s = buf[pos.*..][0..len];
    pos.* += len;
    return s;
}


pub fn encode_owners(allocator: std.mem.Allocator, entries: []const Ownerentry) ![]u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(allocator);

    try out.appendSlice(allocator, magic);

    var verbuf: [2]u8 = undefined;
    std.mem.writeInt(u16, &verbuf, formatvers, .little);
    try out.appendSlice(allocator, &verbuf);

    var countbuf: [4]u8 = undefined;
    std.mem.writeInt(u32, &countbuf, @intCast(entries.len), .little);
    try out.appendSlice(allocator, &countbuf);

    for (entries) |e| {
        try write_f(&out, allocator, e.crel);
        try write_f(&out, allocator, e.reponame);
        try write_f(&out, allocator, e.pkgname);
    }

    const crc = std.hash.Crc32.hash(out.items);
    var crcbuf: [4]u8 = undefined;
    std.mem.writeInt(u32, &crcbuf, crc, .little);
    try out.appendSlice(allocator, &crcbuf);

    return out.toOwnedSlice(allocator);
}

// decodes without copy, buf must outlive the returned slice, same convention as tree.zig
pub fn decode_owners(buf: []const u8, allocator: std.mem.Allocator) ![]Ownerentry {
    if (buf.len < 4 + 2 + 4 + 4) return Ownererror.truncated;
    if (!std.mem.eql(u8, buf[0..4], magic)) return Ownererror.badmagic;

    var pos: usize = 4;
    const version = std.mem.readInt(u16, buf[pos..][0..2], .little);
    pos += 2;
    if (version != formatvers) return Ownererror.unsupportedvers;

    const count = std.mem.readInt(u32, buf[pos..][0..4], .little);
    pos += 4;

    const storedcrc = std.mem.readInt(u32, buf[buf.len - 4 ..][0..4], .little);
    const expectedcrc = std.hash.Crc32.hash(buf[0 .. buf.len - 4]);
    if (storedcrc != expectedcrc) return Ownererror.crcmismatch;

    const entries = try allocator.alloc(Ownerentry, count);
    errdefer allocator.free(entries);

    for (entries) |*e| {
        const crel = read_f(buf, &pos);
        const reponame = read_f(buf, &pos);
        const pkgname = read_f(buf, &pos);
        e.* = .{ .crel = crel, .reponame = reponame, .pkgname = pkgname };
    }

    return entries;
}

// finds who owns a given crel path, if anyone
pub fn find_owner(entries: []const Ownerentry, crel: []const u8) ?Ownerentry {
    for (entries) |e| {
        if (std.mem.eql(u8, e.crel, crel)) return e;
    }
    return null;
}
// is ownedby :shockerface: it, finds what something is owned by
pub fn is_ownedby(entries: []const Ownerentry, crel: []const u8, reponame: []const u8, pkgname: []const u8) bool {
    const owner = find_owner(entries, crel) orelse return false;
    return std.mem.eql(u8, owner.reponame, reponame) and std.mem.eql(u8, owner.pkgname, pkgname);
}