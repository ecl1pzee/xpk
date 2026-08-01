const std = @import("std");
const log = @import("log.zig");
const print = std.debug.print;


// yes, most of this is taken from neo.
// its because its xpk is more of a rewrite with better QOL then a whole new thing
// edit: xpk is NOT a rewrite. this shit is NOT like neo.
// BECAUSE WE NOT ONLY HAVE A 1K LINE PARSER, BUT BINARY FUCKING FORMATS. 
// oh, not to mention, ASYNC.
// yeah. neo is for fucking babies this is for real arasaka supporters.

// to rid of this annoying shit if you hate it
pub var confirmer: bool = true;

pub fn helpmenu() void {
    print(
        \\--- xpk 0.1 ---
        \\
        \\ :: A source based package layer for macOs and Linux.
        \\
        \\USAGE
        \\  xpk [action] [package]
        \\
        \\ACTIONS
        \\
        \\  -a    add        add a package
        \\  -r    remove     remove a package
        \\  -l    list       lists all packages
        \\  -s    search     search for (a) package(s)
        \\  -p    pull       pull in latest commit for mirrorlist
        \\  -u    upgrade    upgrade all installed packages
        \\
    , .{});
}

fn isroot() bool {
    return switch(@import("builtin").os.tag) {
        .linux => std.os.linux.getuid() == 0,
        .macos => std.c.getuid() == 0,
        .dragonfly => std.c.getuid() == 0,
        .netbsd => std.c.getuid() == 0,
        .freebsd => std.c.getuid() == 0,
        .openbsd => std.c.getuid() == 0,
        else => @compileError("not supported Os")
    };
}

pub fn root() !void {
    if (!isroot()) {
        log.err("error, xpk must be run with root for downloads or first time use for setting up directories.\n", .{});
        std.process.exit(1); 
    }
}
// how i feel copy pasting 2 functions
pub fn global_confirmer(io: std.Io) !void {
    if (!confirmer) {
        log.debug1("confirm disabled by config, skipping prompt\n", .{});
        return;
    }

    log.ask("are you sure you want to do this action? [Y/n]: ", .{});
    var buf: [16]u8 = undefined;
    
    var stdin = std.Io.File.stdin().reader(io, &buf);
    
    const input = try stdin.interface.takeDelimiterExclusive('\n');
    if (std.mem.eql(u8,"yes", input) or std.mem.eql(u8, "y", input) or std.mem.eql(u8, "Y", input) or std.mem.eql(u8, "Yes", input)) {
        return;
    } else if (std.mem.eql(u8,"no", input) or std.mem.eql(u8, "n", input) or std.mem.eql(u8, "N", input) or std.mem.eql(u8, "No", input)) {
        std.process.exit(1);
    } else {
        log.fatal("what?\n", .{});
    }
}

pub fn package_confirm(io: std.Io, package: [:0]const u8) !void {
    if (!confirmer) {
        log.debug1("confirm disabled by config, skipping prompt for {s}\n", .{package});
        return;
    }

    log.ask("are you sure you want to download {s}? [Y/n]: ", .{package});
    var buf: [16]u8 = undefined; // PLENTY of bar space
    
    var stdin = std.Io.File.stdin().reader(io, &buf);
    
    const input = try stdin.interface.takeDelimiterExclusive('\n');
    if (std.mem.eql(u8,"yes", input) or std.mem.eql(u8, "y", input) or std.mem.eql(u8, "Y", input) or std.mem.eql(u8, "Yes", input)) {
        return;
    } else if (std.mem.eql(u8,"no", input) or std.mem.eql(u8, "n", input) or std.mem.eql(u8, "N", input) or std.mem.eql(u8, "No", input)) {
        std.process.exit(1);
    } else {
        log.fatal("what?\n", .{});
    }
}

// yeah. it is v0.3.5, because v1 would be a complete 'package manager' with high support, a v3 would be 2 revamps and great ones of it, basically a version change is an extremely large event,
// also doesnt use any of the log shittings because they look weird with \\ spacing
pub fn version() void {
    print(
        \\version 0.3.5, brought to you by sundowner and firewalld, revamp of our beautiful: neo
        \\further development at https://github.com/ecl1pzee/xpk
        \\
    ,.{});
}