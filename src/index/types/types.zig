const std = @import("std");


// fields are in this order, so they can be parsed (duh)
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

   
    // decodes an entry starting a offs in buf, without copy, the returned slices borrow directly from buf so buf must 100% outlive idxentry
    pub fn decode(buf: []const u8, offset: usize) Idxentry {
        var pos = offset;

        // hashing storage logic
        var hash: [32]u8 = undefined;
        @memcpy(&hash, buf[pos..][0..32]);
        pos += 32;

        const name = read_f(buf, &pos);
        const category = read_f(buf, &pos);
        const version = read_f(buf, &pos);
        const description = read_f(buf, &pos);

        return .{
            .xhash = hash,
            .name = name,
            .category = category,
            .version = version,
            .description = description,
        };
    }
    // read_field, reads the field by getting position
    fn read_f(buf: []const u8, pos: *usize) []const u8 {
        const len = std.mem.readInt(u16, buf[pos.*..][0..2], .little);
        pos.* += 2;
        const s = buf[pos.*..][0..len];
        pos.* += len;
        return s;
    }
};


// sig errors
pub const Signederror = error{ truncated, toomanysigners };

// sigs
pub const Sigentry = struct {
    fingerprint: [32]u8,
    signature: [64]u8,
};

pub const Signedidx = struct {
    body: []const u8,      // the original unwrapped index.bin bytes — magic..crc32, this is what mainly gets verified and parsd, also buf most outlive
    sigs: []Sigentry,      // free seperatly

    pub fn deinit(self: *Signedidx, allocator: std.mem.Allocator) void {
        allocator.free(self.sigs);
        self.sigs = &.{};
    }
};

// split_signed a wrapped index.bin into its body 
pub fn split_s(buf: []const u8, allocator: std.mem.Allocator) !Signedidx {
    if (buf.len < 4) return Signederror.truncated;

    const bodylen = std.mem.readInt(u32, buf[0..4], .little);
    var pos: usize = 4;

    if (buf.len < pos + bodylen + 1) return Signederror.truncated; // +1 for sigcount byte
    const body = buf[pos .. pos + bodylen];
    pos += bodylen;

    const sigcount = buf[pos];
    pos += 1;

    const sigbytes: usize = @as(usize, sigcount) * (32 + 64);
    if (buf.len < pos + sigbytes) return Signederror.truncated;

    const sigs = try allocator.alloc(Sigentry, sigcount);
    errdefer allocator.free(sigs);

    for (sigs) |*s| {
        @memcpy(&s.fingerprint, buf[pos .. pos + 32]);
        pos += 32;
        @memcpy(&s.signature, buf[pos .. pos + 64]);
        pos += 64;
    }

    return .{ .body = body, .sigs = sigs };
}