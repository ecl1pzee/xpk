//! log stuff
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

// box-drawing prefixes
const reset = "\x1b[0m";

inline fn cprefix(comptime code: []const u8, comptime prefix: []const u8) []const u8 {
    return "\x1b[" ++ code ++ "m" ++ prefix ++ reset;
}

// auto nest, i js added to make nicer
inline fn nestprefix(comptime depth: usize) []const u8 {
    comptime var buf: []const u8 = "";
    comptime var i: usize = 0;
    inline while (i < depth) : (i += 1) {
        buf = buf ++ "│ ";
    }
    return buf;
}

// slight rework to our logging output
pub inline fn err(comptime fmt: []const u8, args: anytype) void {
    if (!enabled(.err)) return;
    if (color) {
        print(cprefix("31", "├─ x ") ++ fmt, args);
    } else {
        print("├─ x " ++ fmt, args);
    }
}

pub inline fn warn(comptime fmt: []const u8, args: anytype) void {
    if (!enabled(.warn)) return;
    if (color) {
        print(cprefix("33", "├─ ! ") ++ fmt, args);
    } else {
        print("├─ ! " ++ fmt, args);
    }
}

pub inline fn info(comptime fmt: []const u8, args: anytype) void {
    if (!enabled(.info)) return;
    print("├─ " ++ fmt, args);
}

pub inline fn begin(comptime fmt: []const u8, args: anytype) void {
    if (!enabled(.info)) return;
    print("┌─ " ++ fmt, args);
}

pub inline fn success(comptime fmt: []const u8, args: anytype) void {
    if (!enabled(.info)) return;
    if (color) {
        print(cprefix("32", "└─ + ") ++ fmt, args);
    } else {
        print("└─ + " ++ fmt, args);
    }
}

// prompts always print regardless of verbosity
pub inline fn ask(comptime fmt: []const u8, args: anytype) void {
    if (color) {
        print(cprefix("36", "┌─ ? ") ++ fmt, args);
    } else {
        print("┌─ ? " ++ fmt, args);
    }
}

pub inline fn askmid(comptime fmt: []const u8, args: anytype) void {
    if (color) {
        print(cprefix("36", "├─ ? ") ++ fmt, args);
    } else {
        print("├─ ? " ++ fmt, args);
    }
}


// for people that like shit on a golden platter
pub inline fn debug1(comptime fmt: []const u8, args: anytype) void {
    if (!enabled(.debug1)) return;
    print(nestprefix(1) ++ "├─ " ++ fmt, args);
}

// for people that like shit shoved in their face
pub inline fn debug2(comptime fmt: []const u8, args: anytype) void {
    if (!enabled(.debug2)) return;
    print(nestprefix(2) ++ "├─ " ++ fmt, args);
}

// for people that like shit shoved in their face agressively
pub inline fn debug3(comptime fmt: []const u8, args: anytype) void {
    if (!enabled(.debug3)) return;
    print(nestprefix(3) ++ "├─ " ++ fmt, args);
}

// extreme debugging, shows traces, only meant for xpk developers, or if you just like seeing allocator frees and function startups on your system ig
pub inline fn trace(comptime fmt: []const u8, args: anytype) void {
    if (!enabled(.trace)) return;
    print(nestprefix(4) ++ "└─ : " ++ fmt, args);
}

// noreturn
pub inline fn fatal(comptime fmt: []const u8, args: anytype) noreturn {
    if (color) {
        print(cprefix("31", "└─ x FATAL ") ++ fmt, args);
    } else {
        print("└─ x FATAL " ++ fmt, args);
    }
    std.process.exit(1);
}

pub inline fn newline(comptime fmt: []const u8) void {
    print("\n" ++ fmt, .{});
}

//├─ info
//├─ x error
//├─ ! warning
//└─ + success (usually ending messages)

//│ ├─ debug
//│ │ ├─ deeper debug
//│ │ │ ├─ even deeper
//│ │ │ │ └─ : trace