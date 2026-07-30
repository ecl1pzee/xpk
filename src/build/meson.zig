const std = @import("std");
const runner = @import("run.zig");

pub fn build(io: std.Io, allocator: std.mem.Allocator, args: ?[]const []const u8, sourced: []const u8) !void {
    try runner.run(io, allocator, &.{ "meson", "setup", "build" }, args, sourced);
    try runner.run_step(io, allocator, &.{ "meson", "compile", "-C", "build" }, sourced);
}