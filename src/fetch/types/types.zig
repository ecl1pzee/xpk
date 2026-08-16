const std = @import("std");

// added more options because we need our install shit to know alot
pub const Pkgurl = struct {
    allocator: std.mem.Allocator,
    xbuild: ?[]const u8,
    repo: []const u8,
    category: []const u8,
    hash: [32]u8,

    pub fn deinit(self: *Pkgurl) void {
        if (self.xbuild) |m| self.allocator.free(m);
        self.xbuild = null;
    }
};

// imma push this to one file only later 
// readded, because i put whatever i want to use in types/types.zig, and it doesnt contact with 'index' (atleast not yet) so im not putting it in utils
pub const Idxentry = struct {
    xhash: [32]u8,
    name: []const u8,
    category: []const u8,
    version: []const u8,
    description: []const u8,

    // encodes this entry as its binary blob (see layout above)
    pub fn encode(self: Idxentry, allocator: std.mem.Allocator) ![]u8 {
        var blob: std.ArrayList(u8) = .empty;
        errdefer blob.deinit(allocator);

        try blob.appendSlice(allocator, &self.xhash);

        inline for (.{ self.name, self.category, self.version, self.description }) |field| {
            var lenbuf: [2]u8 = undefined;
            std.mem.writeInt(u16, &lenbuf, @intCast(field.len), .little);
            try blob.appendSlice(allocator, &lenbuf);
            try blob.appendSlice(allocator, field);
        }

        return blob.toOwnedSlice(allocator);
    }

   
    // decodes an entry starting at offs in buf, without copy, the returned slices borrow directly from buf so buf must 100% outlive idxentry
    pub fn decode(buf: []const u8, offset: usize) !Idxentry {
        var pos = offset;

        // need at least 32 bytes for the hash
        if (pos + 32 > buf.len) return error.truncated;

        // hashing storage logic
        var hash: [32]u8 = undefined;
        @memcpy(&hash, buf[pos..][0..32]);
        pos += 32;

        const name = try read_f(buf, &pos);
        const category = try read_f(buf, &pos);
        const version = try read_f(buf, &pos);
        const description = try read_f(buf, &pos);

        return .{
            .xhash = hash,
            .name = name,
            .category = category,
            .version = version,
            .description = description,
        };
    }

    // same fix as owners
    fn read_f(buf: []const u8, pos: *usize) ![]const u8 {
        if (pos.* + 2 > buf.len) return error.truncated;
        const len = std.mem.readInt(u16, buf[pos.*..][0..2], .little);
        pos.* += 2;
        if (pos.* + len > buf.len) return error.truncated;
        const s = buf[pos.*..][0..len];
        pos.* += len;
        return s;
    }
};


pub const Idxerror = error{ badmagic, unsupportedvers, crcmismatch, truncated };

const Parsedidx = struct {
    head: [32]u8,
    offsets: []u32,
    entriesst: usize,
};

// walks the header, validates magic/version/crc, hands back the offset table, god i fucking love tables, just tables all over sql shit ykkkkk
pub fn parse_idx(buf: []const u8, allocator: std.mem.Allocator) !Parsedidx {
    if (buf.len < 42 + 4) return Idxerror.truncated;

    if (!std.mem.eql(u8, buf[0..4], "XPKI")) return Idxerror.badmagic;

    var pos: usize = 4;
    const version = std.mem.readInt(u16, buf[pos..][0..2], .little);
    pos += 2;
    if (version != 1) return Idxerror.unsupportedvers;

    var head: [32]u8 = undefined;
    @memcpy(&head, buf[pos..][0..32]);
    pos += 32;

    const count = std.mem.readInt(u32, buf[pos..][0..4], .little);
    pos += 4;

    // make sure there is room for offsets and crc, if there aint, then return truncated error
    const offsbytes: u64 = @as(u64, count) * 4;
    if (buf.len < pos + offsbytes + 4) return Idxerror.truncated;

    // now its safe to check crc and such
    const storedcrc = std.mem.readInt(u32, buf[buf.len - 4 ..][0..4], .little);
    const expectedcrc = std.hash.Crc32.hash(buf[0 .. buf.len - 4]);
    if (storedcrc != expectedcrc) return Idxerror.crcmismatch;

    const offsets = try allocator.alloc(u32, count);
    errdefer allocator.free(offsets);
    for (offsets) |*o| {
        o.* = std.mem.readInt(u32, buf[pos..][0..4], .little);
        pos += 4;
    }

    const entriesst = pos;

    return .{ .head = head, .offsets = offsets, .entriesst = entriesst };
}

// binary search over the sorted offset table, its basically a binary searcher which is super quick
pub fn find_package(buf: []const u8, offsets: []const u32, entriesst: usize, name: []const u8) ?Idxentry {
    var lo: usize = 0;
    var hi: usize = offsets.len;
    while (lo < hi) { // walk and debyg
        const mid = lo + (hi - lo) / 2;
        // nwo erro union
        const entry = Idxentry.decode(buf, entriesst + offsets[mid]) catch return null;
        switch (std.mem.order(u8, entry.name, name)) {
            .eq => return entry,
            .lt => lo = mid + 1,
            .gt => hi = mid,
        }
    }
    return null;
}