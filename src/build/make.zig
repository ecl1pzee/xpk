const std = @import("std");
const runner = @import("run.zig");

// plain make almost never happens, but support cuz its 3 fucking lines now
pub fn build(io: std.Io, allocator: std.mem.Allocator, args: ?[]const []const u8, sourced: []const u8) !void {
    try runner.run(io, allocator, &.{"make"}, args, sourced);
}