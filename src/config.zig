//! loads xpk.conf and applies it to the relevant global state (haha get it global state roblox exploits gcc virus systemd)
//! is simple shit ion gotta write. just uses the parser and does that
const std = @import("std");
const globals = @import("globals.zig");
const parsers = @import("parsers/parsers.zig");
const types = @import("parsers/types/types.zig");
const log = @import("utils/log.zig");
const cli = @import("utils/cli.zig");

pub const Config = types.Config;

pub var current: Config = .{};

// reads globals.conf and parses it, or returns Config{} defaults if it's missing. we should autocreate it anyways or encourage users to do so tho
pub fn load(io: std.Io, allocator: std.mem.Allocator) !Config {
    const bytes = std.Io.Dir.cwd().readFileAlloc(io, globals.conf, allocator, .unlimited) catch |err| switch (err) {
        error.FileNotFound => {
            log.debug1("no xpk.conf found, using defaults\n", .{});
            return .{};
        },
        else => {
            log.err("failed reading xpk.conf: {s}\n", .{@errorName(err)});
            return err;
        },
    };
    defer allocator.free(bytes);

    return parsers.parse_c(allocator, bytes) catch |err| {
        log.err("failed parsing xpk.conf: {s}\n", .{@errorName(err)});
        return err;
    };
}


pub fn apply(cfg: Config) void {
    current = cfg;

    log.level = std.meta.stringToEnum(log.Level, cfg.verbosity) orelse blk: {
        log.warn("unknown verbosity '{s}' in xpk.conf, falling back to info\n", .{cfg.verbosity});
        break :blk .info;
    };

    log.color = cfg.color;
    cli.confirmer = cfg.confirm;

    log.debug2("config applied: verbosity={s} color={} confirm={}\n", .{ cfg.verbosity, cfg.color, cfg.confirm });
}