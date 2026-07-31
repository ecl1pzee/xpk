//! for macos, since sandbox-exec comes preinstalled we just roll that, for linux we are unfortunatlely for the goal of 0 dependencies (that dont come preinstalled as critical packages) will need raw namespaces
const std = @import("std");
const builtin = @import("builtin");
const log = @import("../utils/log.zig");

pub const Sandboxopts = struct {
    allownet: bool,
    writable: []const []const u8,
    readable: []const []const u8,
};


// this will grow and become a big ass global, but this works right now for a majority of packages ive tested (like 2)  so its fine
fn build_mprofile(allocator: std.mem.Allocator, opts: Sandboxopts) ![]u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(allocator);

    try out.appendSlice(allocator,
        \\(version 1)
        \\(deny default)
        \\(allow process-fork)
        \\(allow process-exec)
        \\(allow file-map-executable)
        \\(allow signal (target same-sandbox))
        \\(allow file-read*)
        \\(allow file-write* (literal "/dev/null"))
        \\(allow file-write* (literal "/dev/stdin"))
        \\(allow file-write* (literal "/dev/stdout"))
        \\(allow file-write* (literal "/dev/stderr"))
        \\(allow file-write* (literal "/dev/tty"))
        \\(allow file-write-data (literal "/dev/null"))
        \\(allow file-write-data (literal "/dev/tty"))
        \\(allow file-ioctl (literal "/dev/null"))
        \\(allow file-ioctl (literal "/dev/tty"))
        \\(allow sysctl-read)
        \\(allow mach-lookup)
        \\(allow mach-priv-task-port)
        \\(allow ipc-posix-shm)
        \\(allow system-socket)
        \\(allow file-read-metadata)
        \\
    );

    for (opts.writable) |path| {
        try out.appendSlice(allocator, "(allow file-write* (subpath \"");
        try out.appendSlice(allocator, path);
        try out.appendSlice(allocator, "\"))\n");
    }

    if (opts.allownet) {
        try out.appendSlice(allocator, "(allow network*)\n"); // i'd keep disabled
    }

    return out.toOwnedSlice(allocator);
}

pub const Wrapped = struct {
    argv: [][]const u8,
    ppath: ?[]const u8, // needs cleanup after the process exits

    pub fn deinit(self: *Wrapped, allocator: std.mem.Allocator) void {
        allocator.free(self.argv);
        if (self.ppath) |p| allocator.free(p);
    }
};


// linux sandboxing is gonna be rawnamespaces, no dependencies.
// the only reason i use sandbox-exec for macos is because it comes entirely preinstalled into unwritable /usr/bin, so no point at all to write my own, however:
// for linux, and freebsd, and maybe macos in the future ill design a global one, however for most of the lifespan until a v1/v2 sandboxexec will be used to wrap shell for macos
pub fn wrap(io: std.Io, allocator: std.mem.Allocator, argv: []const []const u8, opts: Sandboxopts) !Wrapped {
    switch (builtin.os.tag) {
        .macos => {
            const profile = try build_mprofile(allocator, opts);
            defer allocator.free(profile);
            // in tmp, because xpk user quite literally cannot write beyond /tmp/xpk 
            const profilepath = try std.fmt.allocPrint(allocator, "/tmp/xpk-sandbox-{d}.sb", .{std.Io.Timestamp.now(io, .real).toSeconds()});
            errdefer allocator.free(profilepath);

            const file = try std.Io.Dir.createFileAbsolute(io, profilepath, .{ .truncate = true });
            defer file.close(io);
            var writerbuf: [4096]u8 = undefined;
            var fwriter = file.writer(io, &writerbuf);
            try fwriter.interface.writeAll(profile);
            try fwriter.interface.flush();

            var wrapped: std.ArrayList([]const u8) = .empty;
            errdefer wrapped.deinit(allocator);
            try wrapped.appendSlice(allocator, &.{ "sandbox-exec", "-f", profilepath });
            try wrapped.appendSlice(allocator, argv);

            return .{ .argv = try wrapped.toOwnedSlice(allocator), .ppath = profilepath };
        },
        .linux => {
            log.warn("linux sandboxing not implemented yet, running unsandboxed\n", .{});
            return .{ .argv = try allocator.dupe([]const u8, argv), .ppath = null };
        },
        else => {
            log.warn("sandboxing not supported on this platform, running unsandboxed\n", .{});
            return .{ .argv = try allocator.dupe([]const u8, argv), .ppath = null };
        },
    }
}