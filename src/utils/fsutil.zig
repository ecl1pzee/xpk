//! fsutil!!!
const std = @import("std");
const log = @import("log.zig");

// recursive mkdir -p usefult ool
pub fn createdir(io: std.Io, path: []const u8) !void {
    std.Io.Dir.cwd().createDirPath(io, path) catch |err| switch (err) {
        error.PathAlreadyExists => {
            log.debug1("directory already exists: {s}\n", .{path});
        },
        else => {
            log.err("failed creating directory {s}: {s}\n", .{path, @errorName(err)});
            return err;
        },
    };
}