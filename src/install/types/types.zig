const std = @import("std");


// basically, neo.files, but in a binary format, we need this so we can easily remove shit and xpk owns /opt/xpk/bin/cmatrix for debuggging and such bla bla bla
pub const Fileentry = struct {
    path: []const u8,
};

pub const Manifesterror = error{ badmagic, unsupportedvers, crcmismatch, truncated };

pub fn parse_m(buf: []const u8, allocator: std.mem.Allocator) ![][]const u8 {
    if (buf.len < 4 + 2 + 4 + 4) return Manifesterror.truncated;
    if (!std.mem.eql(u8, buf[0..4], "XPKF")) return Manifesterror.badmagic;

    var pos: usize = 4;
    const version = std.mem.readInt(u16, buf[pos..][0..2], .little);
    pos += 2;
    if (version != 1) return Manifesterror.unsupportedvers;

    const count = std.mem.readInt(u32, buf[pos..][0..4], .little);
    pos += 4;

    const storedcrc = std.mem.readInt(u32, buf[buf.len - 4 ..][0..4], .little);
    const expectedcrc = std.hash.Crc32.hash(buf[0 .. buf.len - 4]);
    if (storedcrc != expectedcrc) return Manifesterror.crcmismatch;

    const paths = try allocator.alloc([]const u8, count);
    errdefer allocator.free(paths);

    for (paths) |*p| {
        const len = std.mem.readInt(u16, buf[pos..][0..2], .little);
        pos += 2;
        p.* = buf[pos..][0..len];
        pos += len;
    }

    return paths;
}

pub fn encode_m(allocator: std.mem.Allocator, paths: []const []const u8) ![]u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(allocator);

    try out.appendSlice(allocator, "XPKF");

    var verbuf: [2]u8 = undefined;
    std.mem.writeInt(u16, &verbuf, 1, .little);
    try out.appendSlice(allocator, &verbuf);

    var countbuf: [4]u8 = undefined;
    std.mem.writeInt(u32, &countbuf, @intCast(paths.len), .little);
    try out.appendSlice(allocator, &countbuf);

    for (paths) |p| {
        var lenbuf: [2]u8 = undefined;
        std.mem.writeInt(u16, &lenbuf, @intCast(p.len), .little);
        try out.appendSlice(allocator, &lenbuf);
        try out.appendSlice(allocator, p);
    }

    const crc = std.hash.Crc32.hash(out.items);
    var crcbuf: [4]u8 = undefined;
    std.mem.writeInt(u32, &crcbuf, crc, .little);
    try out.appendSlice(allocator, &crcbuf);

    return out.toOwnedSlice(allocator);
}