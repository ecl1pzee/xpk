//! will have outdated hashes such as blake added soon, for purpose of compatibility, although it will be highly encouraged to use sha256
//! will also implement simple keys and trust here
//! will also contain trusted commits, and yeah you guessed it just more stuff for hashing in this file specifically but in the directory much more
//! lmaoo he did not add blake 
//! probs gonna stay that way but we will add smthing eventually
//! 
const std = @import("std");
// expected hash would be whatever you download
pub fn get_hash(file: std.Io.File, io: std.Io, expected: []const u8) !bool {
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

    var digest: [std.crypto.hash.sha2.Sha256.digest_length]u8 = undefined;
    hasher.final(&digest);

    const donehex = std.fmt.bytesToHex(digest, .lower);

    return std.mem.eql(u8, &donehex, expected);
}
// fuck.
pub fn get_hashb(data: []const u8) ![std.crypto.hash.sha2.Sha256.digest_length]u8 {
    var digest: [std.crypto.hash.sha2.Sha256.digest_length]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(data, &digest, .{});
    return digest;
}