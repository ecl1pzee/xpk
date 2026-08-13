//! rework, tree entries are now recursive instead of flat
//! although it does add a little bit of overhead rn since our layouts aren't thousands of files
const std = @import("std");

const magic = "XPKT";
const formatvers: u16 = 2;

// sorts these guys
pub const Kind = enum(u8) { file = 0, dir = 1 };

pub const Treeentry = struct {
    name: []const u8,
    hash: [32]u8,
    mode: u32,
    kind: Kind,
};

pub const Treeerror = error{ badmagic, unsupportedvers, crcmismatch, truncated };

pub fn sort_entries(entries: []Treeentry) void {
    std.mem.sort(Treeentry, entries, {}, struct {
        fn less_t(_: void, a: Treeentry, b: Treeentry) bool {
            return std.mem.order(u8, a.name, b.name) == .lt;
        }
    }.less_t);
}

pub fn encode_tree(allocator: std.mem.Allocator, entries: []const Treeentry, dirmode: u32) ![]u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(allocator);

    try out.appendSlice(allocator, magic);

    var verbuf: [2]u8 = undefined;
    std.mem.writeInt(u16, &verbuf, formatvers, .little);
    try out.appendSlice(allocator, &verbuf);

    var dmbuf: [4]u8 = undefined;
    std.mem.writeInt(u32, &dmbuf, dirmode, .little);
    try out.appendSlice(allocator, &dmbuf);

    var countbuf: [4]u8 = undefined;
    std.mem.writeInt(u32, &countbuf, @intCast(entries.len), .little);
    try out.appendSlice(allocator, &countbuf);

    for (entries) |e| {
        var lenbuf: [2]u8 = undefined;
        std.mem.writeInt(u16, &lenbuf, @intCast(e.name.len), .little);

        try out.appendSlice(allocator, &lenbuf);
        try out.appendSlice(allocator, e.name);

        try out.appendSlice(allocator, &e.hash);

        var modebuf: [4]u8 = undefined;
        std.mem.writeInt(u32, &modebuf, e.mode, .little);
        try out.appendSlice(allocator, &modebuf);

        try out.append(allocator, @intFromEnum(e.kind));
    }

    const crc = std.hash.Crc32.hash(out.items);
    var crcbuf: [4]u8 = undefined;
    std.mem.writeInt(u32, &crcbuf, crc, .little);
    try out.appendSlice(allocator, &crcbuf);

    return out.toOwnedSlice(allocator);
}

pub const Decodedtree = struct {
    entries: []Treeentry,
    dirmode: u32,
};

pub fn decode_tree(buf: []const u8, allocator: std.mem.Allocator) !Decodedtree {
    if (buf.len < 4 + 2 + 4 + 4 + 4) return Treeerror.truncated;
    if (!std.mem.eql(u8, buf[0..4], magic)) return Treeerror.badmagic;

    var pos: usize = 4;
    const version = std.mem.readInt(u16, buf[pos..][0..2], .little);
    pos += 2;
    if (version != formatvers) return Treeerror.unsupportedvers;

    const dirmode = std.mem.readInt(u32, buf[pos..][0..4], .little);
    pos += 4;

    const count = std.mem.readInt(u32, buf[pos..][0..4], .little);
    pos += 4;

    const storedcrc = std.mem.readInt(u32, buf[buf.len - 4 ..][0..4], .little);
    const expectedcrc = std.hash.Crc32.hash(buf[0 .. buf.len - 4]);
    if (storedcrc != expectedcrc) return Treeerror.crcmismatch;

    const entries = try allocator.alloc(Treeentry, count);
    errdefer allocator.free(entries);

    for (entries) |*e| {
        const len = std.mem.readInt(u16, buf[pos..][0..2], .little);
        pos += 2;
        const name = buf[pos..][0..len];
        pos += len;

        var hash: [32]u8 = undefined;
        @memcpy(&hash, buf[pos..][0..32]);
        pos += 32;

        const mode = std.mem.readInt(u32, buf[pos..][0..4], .little);
        pos += 4;

        const kind: Kind = @enumFromInt(buf[pos]);
        pos += 1;

        e.* = .{ .name = name, .hash = hash, .mode = mode, .kind = kind };
    }

    return .{ .entries = entries, .dirmode = dirmode };
}

pub fn hash_tree(blob: []const u8) [32]u8 {
    var digest: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(blob, &digest, .{});
    return digest;
}