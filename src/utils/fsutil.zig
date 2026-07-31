//! fsutil!!! has like 2 functions
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

pub fn rename(io: std.Io, old: []const u8, new: []const u8) !void {
    std.Io.Dir.renameAbsolute(old, new, io) catch |err| switch (err) {
        error.CrossDevice => {
            // rename cannot cross filesystems, so we just stream and delete, also atomic so its better realistically

            const src = try std.Io.Dir.openFileAbsolute(io, old, .{});
            defer src.close(io);

            const dst = try std.Io.Dir.createFileAbsolute(io, new, .{
                .truncate = true,
            });
            defer dst.close(io);

            var writerbuf: [64 * 1024]u8 = undefined;
            var fwriter = dst.writer(io, &writerbuf);
            const writer = &fwriter.interface;

            var buf: [64 * 1024]u8 = undefined;
            var freader = src.reader(io, &buf);
            const reader = &freader.interface;

            while (true) {
                const n = try reader.readSliceShort(&buf);
                

                if (n == 0)
                    break;

                try writer.writeAll(buf[0..n]);
            }
    
            try writer.flush();

            try std.Io.Dir.deleteFileAbsolute(io, old);
        },
        else => return err,
    };
}
