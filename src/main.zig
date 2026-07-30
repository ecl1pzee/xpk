//! sigma
const std = @import("std");
const globals = @import("globals.zig");
const utils = @import("utils/utils.zig");
const installer = @import("installer.zig");
const print = std.debug.print;

// globals here
const allocator = std.heap.smp_allocator; // for actual programs, arena allocator below for args (because frees all at once at program end)

// unlike backthen with neo, where i was learning zig and i desrcibed alot of my actions in code to remember them, i won't do the same here.
// HOWEVER most of the code is gonna remain somewhat the same, except the idea is quite quite different now.

// rules for codebase!
// inside of functions lowercase only, structs must be first letter upercase, idealy, functions should have a snakecase and a shortened aftername.

// yeah thats it, try to put some comments to your code and patches too. 
// please use 64 kb for any transfer buffer or writer buffer. (sweet spot, and for normal macs usually doesn't cause issues even with multiple concurrent streaming, and reduces syscall usage)

// most importantly, please organize code and any new large additions, please add unit tests.
// please unroll and abstract any sort of formatting in this way:
// const something = try function( 
//      arg1,
//      arg2,
//      arg3
//       ,.{}
//);
// (specifically for formatting, it helps alot to read what you are trying to format. ))

// please, for readability of functions, place all allocators and ios first (i usually put io and allocator first, then after anything like client, or any multi use things)
// this makes reading really easy because you can just look at the end of the function to see what it needs


// macros for prints ()
// only place i used comptime so far
inline fn errprint(comptime fmt: []const u8, args: anytype) void {
    print("[x] " ++ fmt, args);
}

inline fn iprint(comptime fmt: []const u8, args: anytype) void {
    print("[*] " ++ fmt, args);
}

inline fn wprint(comptime fmt: []const u8, args: anytype) void {
    print("[!] " ++ fmt, args);
}


fn createdir(io: std.Io, path: []const u8) !void {
    std.Io.Dir.createDirAbsolute(
        io,
        path,
        .default_dir,
    ) catch |err| switch (err) {
        error.PathAlreadyExists => {},
        else => return err,
    };
}

pub fn ensure_xpk(io: std.Io) !void {
    const marker = std.Io.Dir.openFileAbsolute(io, globals.firstrun, .{ .mode = .read_only }) catch |err| switch (err) {
        error.FileNotFound => null, // yayyy zig specific error that doesn't match my naming convention woohoo
        else => return err,
    };
    if (marker) |file| {
        file.close(io);
        return; // if file exists, then xpk has already been ran and yeah we dont run again yay
    }

    try utils.cli.root();

    // set up all globals
    iprint("setting up globals...\n", .{});
    try createdir(io, globals.base);
    try createdir(io, globals.db);
    try createdir(io, globals.local);
    try createdir(io, globals.tmp);
    try utils.sync.init_repo(io);


    iprint("done settin up xpk! enjoy!!\n", .{});
    // drop
    const file = try std.Io.Dir.createFileAbsolute(io, globals.firstrun, .{ .truncate = false });
    defer file.close(io);
}

pub fn main(init: std.process.Init) !void {
    const io = init.io; 
    
    const arena = init.arena.allocator(); // only for args. do not use for any actual package manager allocations.
    const args = try init.minimal.args.toSlice(arena);

    // tmp is wiped every reboot, so its only normal if i put it in here
    try createdir(io, globals.tmp); 

    // creation all in function
    try ensure_xpk(io);

    // args[1] is cmd.

    if (args.len < 2) {
        iprint("usage: xpk <action> for more info do 'xpk help'\n", .{});
        return;
    } else 
    

    if (std.mem.eql(u8, args[1], "-h") or std.mem.eql(u8, args[1], "help")) {
        utils.cli.helpmenu();
        return;
    } else 
    
    if (std.mem.eql(u8, args[1], "add") or std.mem.eql(u8, args[1], "-a") or std.mem.eql(u8, args[1], "install")) {
        if (args.len < 3) {
            iprint("usage is xpk install <package>\n", .{});
            return;
        }
        try utils.cli.root();
        const package = args[2];
        try utils.cli.package_confirm(io, package);
        try installer.get_package(io, allocator, package);
        return;
    } else 

    if (std.mem.eql(u8, args[1], "list")) {
        try utils.misc.list(io, allocator);
    } else 

    if (std.mem.eql(u8, args[1], "info")) {
        const package = args[2];
        try utils.misc.info(io, allocator, package);
    } else 

    if (std.mem.eql(u8, args[1], "search") or std.mem.eql(u8, args[1], "-s")) {
        const query = args[2];
        try utils.misc.search(io, allocator, query);
    } else 

    if (std.mem.eql(u8, args[1], "version") or std.mem.eql(u8, args[1] ,"-v")) {
        utils.cli.version();
        return;
    } else 

    // index requires root now because of the key signing system
    if (std.mem.eql(u8, args[1], "index")) {
        if (args.len < 3) {
            iprint("usage is xpk index <path to repo, locally>\n", .{});
            return;
        }
        try utils.cli.root();
        const kp = utils.security.key_l(io) catch |err| switch (err) {
            error.FileNotFound => {
                wprint("no signing key found, run 'xpk keygen' first\n", .{});
                return;
            },
            error.insecurekeypermissions => {
                errprint("signing key has bad permissions, refusing to index see the earlier warning\n", .{});
                return;
            },
        else => return err,
        };
        try utils.indexer.index_repo(io, allocator, args[2], kp);
    } else 

    if (std.mem.eql(u8, args[1], "pull") or std.mem.eql(u8, args[1], "sync") or std.mem.eql(u8, args[1], "-p")) {
        try utils.cli.root();
        try utils.sync.pull_repo(io, allocator);
        return;
    } else 
    
    if (std.mem.eql(u8, args[1], "keygen")) {
        try utils.cli.root();
        try utils.security.generate(io);
    }

    else {
        wprint("what the hell does that mean. \n", .{});
    }
    
}


