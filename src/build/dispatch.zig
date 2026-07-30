const std = @import("std");
const runner = @import("run.zig");
const cmake = @import("cmake.zig");
const make = @import("make.zig");
const meson = @import("meson.zig");
const utils = @import("../utils/utils.zig");
const autotools = @import("autotools.zig");
const config = @import("../config.zig");
const print = std.debug.print;

inline fn wprint(comptime fmt: []const u8, args: anytype) void {
    print("[!] " ++ fmt, args);
}

const buildf = *const fn (std.Io, std.mem.Allocator, ?[]const []const u8, []const u8) anyerror!void;
// first use of that shit for easier sorting instead of longass if statements (since i did a recode on build)
const buildsystems = std.StaticStringMap(buildf).initComptime(.{
    .{ "cmake", cmake.build },
    .{ "make", make.build },
    .{ "meson", meson.build },
    .{ "autotools", autotools.build },
});

// changed these, although it is recommended to keep xpk user as is, you can make your home user do this, etc.
fn ensure_buildusr(io: std.Io) !void {
    var child = std.process.spawn(io, .{
        .argv = &.{ "id", "-u", config.current.build_usr },
        .stdout = .ignore,
        .stderr = .ignore,
    }) catch return error.buildusermissing;

    const term = try child.wait(io);
    switch (term) {
        .exited => |code| {
            if (code != 0) {
                wprint("build user '{s}' not found. run scripts/needed/setup-xpk-build-user.sh from the repo scripts first\n", .{config.current.build_usr});
                return error.buildusermissing;
            }
        },
        else => return error.buildusermissing,
    }
}

fn ensure_own(io: std.Io, sourced: []const u8) !void {
    var child = std.process.spawn(io, .{
        .argv = &.{ "chown", "-R", config.current.build_usr, sourced },
        .stdout = .ignore,
        .stderr = .ignore,
    }) catch return error.chownfailed;

    const term = try child.wait(io);
    switch (term) {
        .exited => |code| {
            if (code != 0) {
                wprint("failed to chown {s} to build user '{s}', build steps will likely fail\n", .{ sourced, config.current.build_usr });
                return error.chownfailed;
            }
        },
        else => return error.chownfailed,
    }
}

// build function down heei
pub fn run_build(io: std.Io, allocator: std.mem.Allocator, build: utils.parser.Build, pkg: utils.parser.Pkg, sourced: []const u8) !void {
    try ensure_buildusr(io);
    try ensure_own(io, sourced);

    if (pkg.pre_hooks) |hooks| {
        for (hooks) |hook| try runner.run_step(io, allocator, &.{ "sh", "-c", hook }, sourced);
    }

    const bfn = buildsystems.get(build.build_sys) orelse {
        wprint("unsupported build system: {s}\n", .{build.build_sys});
        return error.unsupportedbuildsystem;
    };
    try bfn(io, allocator, build.args, sourced);

    if (build.script) |script| {
        try runner.run_step(io, allocator, &.{ "sh", "-c", script }, sourced);
    }

    if (build.post_hooks) |hooks| {
        for (hooks) |hook| try runner.run_step(io, allocator, &.{ "sh", "-c", hook }, sourced);
    }
}