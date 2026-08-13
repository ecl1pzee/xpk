const std = @import("std");
const testing = std.testing;
const hasher = @import("hasher.zig");

// YO WHY DO I EVEN HAVE THIS OF COURSE IT WORKS

test "get_hash matches known sha256 for known content (which should happen)" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();

    const content = "hello world";
    // known hash for hell wolrd
    const expected = "b94d27b9934d3e08a52e52d7da7dabfac484efe37a5380ee9088f7ace2efcde9";

    const file = try tmp.dir.createFile(testing.io, "test.txt", .{});
    defer file.close(testing.io);
    
    var writerbuf: [64 * 1024]u8 = undefined; // keep 64, benchmark 128 later

    var fwriter = file.writer(testing.io, &writerbuf);
    var writer = &fwriter.interface; // ptr so we get live instance and we can pass const, this required 20 m of debugging. FUCK. ME.

    try writer.writeAll(content);
    try writer.flush();
    
    // reopen for handle
    const rfile = try tmp.dir.openFile(testing.io, "test.txt", .{ .mode = .read_only });
    defer rfile.close(testing.io);


    const result = try hasher.get_hash(rfile, testing.io, expected);
    try testing.expect(result);
}

test "get_hash rejects wrong hash (which should happen)" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();

    const content = "hello world";
    const wronghex = "0000000000000000000000000000000000000000000000000000000000000000";

    const file = try tmp.dir.createFile(testing.io, "test.txt", .{});
    defer file.close(testing.io);
    
    var writerbuf: [64 * 1024]u8 = undefined; // keep 64, benchmark 128 later

    var fwriter = file.writer(testing.io, &writerbuf);
    var writer = &fwriter.interface; // ptr so we get live instance and we can pass const, this required 20 m of debugging. FUCK.

    try writer.writeAll(content);
    try writer.flush();

    const rfile = try tmp.dir.openFile(testing.io, "test.txt", .{ .mode = .read_only });
    defer rfile.close(testing.io);

    const result = try hasher.get_hash(rfile, testing.io, wronghex);
    try testing.expect(!result);
}