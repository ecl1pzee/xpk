const std = @import("std");
const print = std.debug.print;
const config = @import("../config.zig");
const sandbox = @import("../sandbox/sandbox.zig");

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
    try cmd.appendSlice(allocator, "\"; export TMPDIR=\"/tmp/xpk/\"; ");
    // try cmd.appendSlice(allocator, "export SOURCE_DATE_EPOCH=\"1735689600\"; "); // instead of the usual 1970, its 2025-01-01, also dont rlly need this anymore since im going a diff approach, or ill use later in v1.5

    // so, this fucks up any build that doesnt support this option but makes cmatrix reproducable, amazing, imma keep commented and fix up a solution tommorow, or roughly whenever i want reproducible packages
    //if (@import("builtin").target.os.tag == .macos) {
    //   try cmd.appendSlice(allocator, "export LDFLAGS=\"-Wl,-no_uuid\"; ");
    //} 

    for (argv, 0..) |arg, i| {
        if (i != 0) try cmd.append(allocator, ' ');
        try shell_quote(allocator, &cmd, arg);
    }

    return cmd.toOwnedSlice(allocator);
}

// sandboxed, allows writable to both /tmp and /private tmp to abide with macos linkings
pub fn run_step(io: std.Io, allocator: std.mem.Allocator, argv: []const []const u8, cwdp: []const u8) !void {
    const cmd = try build_dropped(allocator, argv);
    defer allocator.free(cmd);

    var wrapped: ?sandbox.Wrapped = null;
    defer if (wrapped) |*w| w.deinit(allocator);

    const finalcmd: []const u8 = cmd;

    if (config.current.sandbox) {
        const opts = sandbox.Sandboxopts{
            .allownet = config.current.sandbox_net,
            .writable = &.{ cwdp, "/tmp", "/private/tmp" },
            .readable = &.{},
        };

       
        wrapped = try sandbox.wrap(io, allocator, &.{ "sh", "-c", cmd }, opts);
    }
    // wraps args with su in the sandbox
    const suargv: []const []const u8 = if (wrapped) |w|
        &.{ "su", config.current.build_usr, "-c", try join_argv(allocator, w.argv) }
    else
        &.{ "su", config.current.build_usr, "-c", finalcmd };

    var child = try std.process.spawn(io, .{
        .argv = suargv,
        .cwd = .{ .path = cwdp },
    });

    const term = try child.wait(io);

    if (wrapped) |w| {
        if (w.ppath) |p| std.Io.Dir.deleteFileAbsolute(io, p) catch {};
    }

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

fn join_argv(allocator: std.mem.Allocator, argv: []const []const u8) ![]const u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(allocator);
    for (argv, 0..) |a, i| {
        if (i != 0) try out.append(allocator, ' ');
        try shell_quote(allocator, &out, a);
    }
    return out.toOwnedSlice(allocator);
}

// less of a wrapper more of a run with args, so i dont have to do alot of shit in the other files and it looks cleaner
pub fn run(io: std.Io, allocator: std.mem.Allocator, prefix: []const []const u8, args: ?[]const []const u8, sourced: []const u8) !void {
    var argv: std.ArrayList([]const u8) = .empty;
    defer argv.deinit(allocator);

    try argv.appendSlice(allocator, prefix);
    if (args) |a| try argv.appendSlice(allocator, a);

    try run_step(io, allocator, argv.items, sourced);
}



