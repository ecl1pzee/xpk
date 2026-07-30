const std = @import("std");
const utils = @import("utils/utils.zig");
const globals = @import("globals.zig");
const db = @import("db/db.zig");
const install = @import("install/install.zig").install;
const print = std.debug.print;


inline fn errprint(comptime fmt: []const u8, args: anytype) void {
    print("[x] " ++ fmt, args);
}

inline fn iprint(comptime fmt: []const u8, args: anytype) void {
    print("[*] " ++ fmt, args);
}

inline fn wprint(comptime fmt: []const u8, args: anytype) void {
    print("[!] " ++ fmt, args);
}

pub fn get_package(io: std.Io, allocator: std.mem.Allocator, package: [:0]const u8) !void {
    var pkgurl = try utils.installer.remote_fetch(io, allocator, package);
    defer pkgurl.deinit();
    
    // before i did renaming i still had pkgurl.manifest, and i was too lazy to change to pkurl.info
    const xbuild = try utils.parser.parse_a(allocator, pkgurl.xbuild.?);


    iprint("downloading {s}", .{package});
    
    const tarball = try utils.installer.download(io, allocator, xbuild.pkg.src_url, false);

    const tarballhandle = try std.Io.Dir.openFileAbsolute(io, tarball, .{.mode = .read_only});
    defer tarballhandle.close(io);

    // safety first kids
    if (!try utils.security.get_hash(tarballhandle, io, xbuild.pkg.sha256sum)) {
        errprint("sha256 checksum verification failed\n", .{});
        return error.invalidchecksum;
    }

    // shitty code logic instead of just fixing it in parser.zig, but im tryna make work first, ill fix later
    var strip: u32 = 0; //edefault
    if (xbuild.pkg.strip) |estriper| {
        if (std.mem.eql(u8, estriper, "1")) {
            strip = 1;
        } else if (std.mem.eql(u8, estriper, "2")) {
            strip = 2;
        } else if (std.mem.eql(u8, estriper, "3")) {
            strip = 3;
        }
    }

    
    const out = try utils.extract.extract_tar(io, allocator, tarball, strip);

    // i need this to return something later so when i make an installer it can grab like, yeah idk
    try utils.builder.run_build(io, allocator, xbuild.build, xbuild.pkg, out);

    
    try install(io,allocator,out,pkgurl.repo,xbuild.info.name,pkgurl.category,xbuild.info.version,pkgurl.hash,xbuild.build.build_sys);
    

    iprint("installed {s} {s}\n", .{xbuild.info.name, xbuild.info.version});
}  