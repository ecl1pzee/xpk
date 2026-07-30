const std = @import("std");


// basically, same as index files i went over a binary format here, but this contains the 'base info' of all packages, while the actual remove info is contained in /opt/xpk/db/(reponame)/files
// but yeah these are the same shit as index, and all use crc for checking
// so it doesnt become a pain in the ass later, but otherwise its very simmilar to idxentry

const magic = "XPKD";
const formatvers: u16 = 2; // two

pub const Dbentry = struct {
    name: []const u8,
    category: []const u8,
    version: []const u8,
    repo: []const u8,       // which repo this came from, helps prevent name cols
    xhash: [32]u8,          // hash of the xbuild that installed it, ties to index
    objhash: [32]u8,        // hash of the built object tree, ties to /opt/xpk/objects/name-version-(hash goes here)
    installedt: i64,        // toseconds timestamp
    generation: u32,        // generation of package

    pub fn encode(self: Dbentry, allocator: std.mem.Allocator) ![]u8 {
        var blob: std.ArrayList(u8) = .empty;
        errdefer blob.deinit(allocator);
        // is better for inline
        inline for (.{ self.name, self.category, self.version, self.repo }) |field| {
            var lenbuf: [2]u8 = undefined;
            std.mem.writeInt(u16, &lenbuf, @intCast(field.len), .little);
            try blob.appendSlice(allocator, &lenbuf);
            try blob.appendSlice(allocator, field);
        }

        try blob.appendSlice(allocator, &self.xhash);
        try blob.appendSlice(allocator, &self.objhash);

        var tsbuf: [8]u8 = undefined;
        std.mem.writeInt(i64, &tsbuf, self.installedt, .little);
        try blob.appendSlice(allocator, &tsbuf);

        var genbuf: [4]u8 = undefined;
        std.mem.writeInt(u32, &genbuf, self.generation, .little);
        try blob.appendSlice(allocator, &genbuf);

        return blob.toOwnedSlice(allocator);
    }

    pub fn decode(buf: []const u8, pos: *usize, allocator: std.mem.Allocator) !Dbentry {
        const name = try allocator.dupe(u8, read_f(buf, pos));
        const category = try allocator.dupe(u8, read_f(buf, pos));
        const version = try allocator.dupe(u8, read_f(buf, pos));
        const repo = try allocator.dupe(u8, read_f(buf, pos));

        var xhash: [32]u8 = undefined;
        @memcpy(&xhash, buf[pos.*..][0..32]);
        pos.* += 32;

        var objhash: [32]u8 = undefined;
        @memcpy(&objhash, buf[pos.*..][0..32]);
        pos.* += 32;

        const ts = std.mem.readInt(i64, buf[pos.*..][0..8], .little);
        pos.* += 8;

        const generation = std.mem.readInt(u32, buf[pos.*..][0..4], .little);
        pos.* += 4;

        return .{
            .name = name,
            .category = category,
            .version = version,
            .repo = repo,
            .xhash = xhash,
            .objhash = objhash,
            .installedt = ts,
            .generation = generation,
        };
    }

    fn read_f(buf: []const u8, pos: *usize) []const u8 {
        const len = std.mem.readInt(u16, buf[pos.*..][0..2], .little);
        pos.* += 2;
        const s = buf[pos.*..][0..len];
        pos.* += len;
        return s;
    }


    pub fn deinit(self: Dbentry, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
        allocator.free(self.category);
        allocator.free(self.version);
        allocator.free(self.repo);
    }
};

pub const Dberror = error{ badmagic, unsupportedvers, crcmismatch, truncated };

pub fn parse_db(buf: []const u8, allocator: std.mem.Allocator) ![]Dbentry {
    if (buf.len < 4 + 2 + 4 + 4) return Dberror.truncated;
    if (!std.mem.eql(u8, buf[0..4], magic)) return Dberror.badmagic;

    var pos: usize = 4;
    const version = std.mem.readInt(u16, buf[pos..][0..2], .little);
    pos += 2;
    if (version != formatvers) return Dberror.unsupportedvers;

    const count = std.mem.readInt(u32, buf[pos..][0..4], .little);
    pos += 4;

    const storedcrc = std.mem.readInt(u32, buf[buf.len - 4 ..][0..4], .little);
    const expectedcrc = std.hash.Crc32.hash(buf[0 .. buf.len - 4]);
    if (storedcrc != expectedcrc) return Dberror.crcmismatch;

    const entries = try allocator.alloc(Dbentry, count);
    errdefer allocator.free(entries);

    for (entries) |*e| {
        e.* = try Dbentry.decode(buf, &pos, allocator);
    }

    return entries;
}

pub fn encode_db(allocator: std.mem.Allocator, entries: []const Dbentry) ![]u8 {
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
        const blob = try e.encode(allocator);
        defer allocator.free(blob);
        try out.appendSlice(allocator, blob);
    }

    const crc = std.hash.Crc32.hash(out.items);
    var crcbuf: [4]u8 = undefined;
    std.mem.writeInt(u32, &crcbuf, crc, .little);
    try out.appendSlice(allocator, &crcbuf);

    return out.toOwnedSlice(allocator);
}