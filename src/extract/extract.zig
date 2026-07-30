//! rewritten right before commit so it has more LESS determinstic unpacking what am i on 
const std = @import("std");
const globals = @import("../globals.zig");
const log = @import("../utils/log.zig");
const utils = @import("../utils/utils.zig");


// luckily, due to the new zig 0.16.0 api:
// i dont need to make specific functions for each extraction
// which is amazing.

fn createdir(io: std.Io, path: []const u8) !void {
    return utils.fs.createdir(io, path);
}



// extract tar, does what it says
pub fn extract_tar(io: std.Io, allocator: std.mem.Allocator, tarballpath: []const u8, strip: u32) ![]const u8 {

    //  gets basename and then just removes suffix, most extracted package names will be different from what they are supposed to be howvevr is a good solution
    const basename = std.fs.path.basename(tarballpath);
    var name = basename;
    for ([_][]const u8{ ".tar.xz", ".tar.zst", ".tar.gz", ".tgz", ".tar" }) |suffix| {
        if (std.mem.endsWith(u8, name, suffix)) {
            name = name[0 .. name.len - suffix.len];
            break;
        }
    } // will add more later so might add sometjing simmilar to categorires in neo

    // direct extraction, and we return extractdir
    const extractdir = try std.fs.path.join(allocator, &.{ globals.tmp, name });
    errdefer allocator.free(extractdir);
    try createdir(io, extractdir);

    var destination = try std.Io.Dir.openDirAbsolute(io, extractdir, .{}); // was globals.tmp, now extract dir  because we make globals.tmp in installer.zig
    defer destination.close(io);

    const file = try std.Io.Dir.openFileAbsolute(io, tarballpath, .{ .mode = .read_only });
    defer file.close(io);

    var readbuf: [64 * 1024]u8 = undefined;
    var freader = file.reader(io, &readbuf);

    // now driven by the spec sheet instead of being hardcoded
    const opts = std.tar.ExtractOptions{ .strip_components = strip }; // can be 0, to not strip at all
    

    // ill support more compression algos next time because im pretty sure zig allows more like lzma (NO one is using it)
    if (std.mem.endsWith(u8, tarballpath, ".xz")) {
        const dictbuf = try allocator.alloc(u8, 1 << 20);
        defer allocator.free(dictbuf);

        var decomp = try std.compress.xz.Decompress.init(&freader.interface, allocator, dictbuf);
        try std.tar.extract(io, destination, &decomp.reader, opts);

    } else if (std.mem.endsWith(u8, tarballpath, ".zst")) {
        const windowlen = std.compress.zstd.default_window_len;
        const outputbuf = try allocator.alloc(u8, windowlen + std.compress.zstd.block_size_max);
        defer allocator.free(outputbuf);

        var decomp = std.compress.zstd.Decompress.init(&freader.interface, outputbuf, .{});
        try std.tar.extract(io, destination, &decomp.reader, opts); 

    } else if (std.mem.endsWith(u8, tarballpath, ".gz") or std.mem.endsWith(u8, tarballpath, ".tgz")) {
        var flatebuf: [64 * 1024]u8 = undefined;
        var decomp = std.compress.flate.Decompress.init(&freader.interface, .gzip, &flatebuf);

        try std.tar.extract(io, destination, &decomp.reader, opts); 
    } else {
        log.err("unsupported tarball extension: {s}\n", .{tarballpath});
        return error.unsupportedcompressedarchive; // returns this t know its bad, i will add support for basically every single one tho
    }

    return extractdir; 
}