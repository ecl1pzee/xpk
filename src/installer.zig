//! installer file,kind of the neo src/download/fetch.zig, but insteaf 100000x better then that
const std = @import("std");
const utils = @import("utils/utils.zig");
const globals = @import("globals.zig");
const db = @import("db/db.zig");
const install = @import("install/install.zig").install;
const log = @import("utils/log.zig");
const config = @import("config.zig");

pub fn get_package(io: std.Io, allocator: std.mem.Allocator, package: [:0]const u8) !void {
    try tmp_chown(io, globals.tmp);
    var pkgurl = try utils.installer.remote_fetch(io, allocator, package);
    defer pkgurl.deinit();
    
    // before i did renaming i still had pkgurl.manifest, and i was too lazy to change to pkurl.info
    const xbuild = try utils.parser.parse_a(allocator, pkgurl.xbuild.?);

    log.info("downloading {s}", .{package});
    
    const tarball = try utils.installer.download(io, allocator, xbuild.pkg.src_url, false);

    const tarballhandle = try std.Io.Dir.openFileAbsolute(io, tarball, .{.mode = .read_only});
    defer tarballhandle.close(io);

    // safety first kids
    if (!try utils.security.get_hash(tarballhandle, io, xbuild.pkg.sha256sum)) {
        log.err("sha256 checksum verification failed\n", .{});
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
    
    log.debug1("cleaning up /tmp/xpk artifacts\n", .{});
    
    {
        var parent = try std.Io.Dir.openDirAbsolute(io, "/tmp", .{});
        defer parent.close(io);
        parent.deleteTree(io, "xpk") catch |err|  {
            log.err("error, was not able to delete /tmp artifacts", .{});
            return err;
        };
    }

    if (xbuild.info.message) |msg| {
        if (msg.len > 0) {
            log.print("package ->{s}<{s}> has a message for you!\n", .{xbuild.info.name, xbuild.info.version}); 
            log.print("========================================", .{}); 
            log.print("{s}\n", .{msg}); // does not support newlines rn, and i could do some tweaks like "indexof/contains" to parse for newlines and print them, but im lazy rn, so ill do that later
        }
    }

    log.success("installed {s} {s}\n", .{xbuild.info.name, xbuild.info.version});
}  

fn tmp_chown(io: std.Io, path: []const u8) !void {
    var child = try std.process.spawn(io, .{
        .argv = &.{ "chown", "-R", config.current.build_usr, path },
        .stdout = .ignore,
        .stderr = .inherit,
    });
    switch (try child.wait(io)) {
        .exited => |code| {
            if (code != 0) {
                log.err("failed to chown {s} to build user, exit {d}\n", .{ path, code });
                return error.chownfailed;
            }
        },
        else => return error.chownfailed,
    }
}
