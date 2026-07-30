const std = @import("std");
const print = std.debug.print;
const config = @import("../config.zig");

// safens shellquoting, and unfucks it up
fn shell_quote(allocator: std.mem.Allocator, out: *std.ArrayList(u8), arg: []const u8) !void {
    try out.append(allocator, '\'');
    for (arg) |c| {
        if (c == '\'') {
            try out.appendSlice(allocator, "'\\''");
        } else {
            try out.append(allocator, c);
        }
    }
    try out.append(allocator, '\'');
}

// builds path
fn build_dropped(allocator: std.mem.Allocator, argv: []const []const u8) ![]u8 {
    var cmd: std.ArrayList(u8) = .empty;
    errdefer cmd.deinit(allocator);

    try cmd.appendSlice(allocator, "export PATH=\"");
    try cmd.appendSlice(allocator, config.current.build_path);
    try cmd.appendSlice(allocator, "\"; ");

    for (argv, 0..) |arg, i| {
        if (i != 0) try cmd.append(allocator, ' ');
        try shell_quote(allocator, &cmd, arg);
    }

    return cmd.toOwnedSlice(allocator);
}

// this one actually runs as user xpk (or whatever build-usr is set to in xpk.conf)
pub fn run_step(io: std.Io, allocator: std.mem.Allocator, argv: []const []const u8, cwdp: []const u8) !void {
    const cmd = try build_dropped(allocator, argv);
    defer allocator.free(cmd);

    var child = try std.process.spawn(io, .{
        .argv = &.{ "su", config.current.build_usr, "-c", cmd },
        .cwd = .{ .path = cwdp },
    });

   

    const term = try child.wait(io);
    switch (term) {
        .exited => |code| {
            if (code != 0) {
                print("command has failed with exit code {d}: {s}\n", .{ code, argv[0] });
                return error.buildstepfailed;
            }
        },
        .signal => |sig| {
            print("command killed by signal {d}: {s}\n", .{ @intFromEnum(sig), argv[0] });
            return error.buildstepfailed;
        },
        .stopped, .unknown => {
            print("command ended unexpectedly: {s}\n", .{argv[0]});
            return error.buildstepfailed;
        },
    }
}

// less of a wrapper more of a run with args, so i dont have to do alot of shit in the other files and it looks cleaner
pub fn run(io: std.Io, allocator: std.mem.Allocator, prefix: []const []const u8, args: ?[]const []const u8, sourced: []const u8) !void {
    var argv: std.ArrayList([]const u8) = .empty;
    defer argv.deinit(allocator);

    try argv.appendSlice(allocator, prefix);
    if (args) |a| try argv.appendSlice(allocator, a);

    try run_step(io, allocator, argv.items, sourced);
}