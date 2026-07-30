const std = @import("std");

pub const print = std.debug.print;

pub const Level = enum(u8) {
    quiet = 0,
    err = 1,
    warn = 2,
    info = 3,
    debug1 = 4,
    debug2 = 5,
    debug3 = 6,
    trace = 7,
};

pub var level: Level = .info;
pub var color: bool = false; // set from xpk.conf's [core] color, defaults off, i hate colors but maybe some will like it

inline fn enabled(required: Level) bool {
    return @intFromEnum(level) >= @intFromEnum(required);
}

// wrapp prefixes,
const reset = "\x1b[0m";

inline fn cprefix(comptime code: []const u8, comptime prefix: []const u8) []const u8 {
    return "\x1b[" ++ code ++ "m" ++ prefix ++ reset;
}

pub inline fn err(comptime fmt: []const u8, args: anytype) void {
    if (!enabled(.err)) return;
    if (color) {
        print(cprefix("31", "[x] ") ++ fmt, args);
    } else {
        print("[x] " ++ fmt, args);
    }
}

pub inline fn warn(comptime fmt: []const u8, args: anytype) void {
    if (!enabled(.warn)) return;
    if (color) {
        print(cprefix("33", "[!] ") ++ fmt, args);
    } else {
        print("[!] " ++ fmt, args);
    }
}

pub inline fn info(comptime fmt: []const u8, args: anytype) void {
    if (!enabled(.info)) return;
    print("[*] " ++ fmt, args);
}

pub inline fn success(comptime fmt: []const u8, args: anytype) void {
    if (!enabled(.info)) return;
    if (color) {
        print(cprefix("32", "[+] ") ++ fmt, args);
    } else {
        print("[+] " ++ fmt, args);
    }
}

// prompts always print regardless of verbosity
pub inline fn ask(comptime fmt: []const u8, args: anytype) void {
    if (color) {
        print(cprefix("36", "[?] ") ++ fmt, args);
    } else {
        print("[?] " ++ fmt, args);
    }
}
// for people that like shit on a golden platter
pub inline fn debug1(comptime fmt: []const u8, args: anytype) void {
    if (!enabled(.debug1)) return;
    print("[#] " ++ fmt, args);
}
// for people that like shit shoved in their face
pub inline fn debug2(comptime fmt: []const u8, args: anytype) void {
    if (!enabled(.debug2)) return;
    print("[##] " ++ fmt, args);
}
// for people that like shit shoved in their face agressively
pub inline fn debug3(comptime fmt: []const u8, args: anytype) void {
    if (!enabled(.debug3)) return;
    print("[###] " ++ fmt, args);
}
// extreme debugging, shows traces, only meant for xpk developers, not users, this would show allocator freeing, and so on and so forth,
pub inline fn trace(comptime fmt: []const u8, args: anytype) void {
    if (!enabled(.trace)) return;
    print("[~] " ++ fmt, args);
}
// noreturn
pub inline fn fatal(comptime fmt: []const u8, args: anytype) noreturn {
    if (color) {
        print(cprefix("31", "[fatal] ") ++ fmt, args);
    } else {
        print("[fatal] " ++ fmt, args);
    }
    std.process.exit(1);
}

pub inline fn newline(comptime fmt: []const u8) void {
    print("\n" ++ fmt, .{});
}

