const std = @import("std");
const globals = @import("../globals.zig");
const downloader = @import("../downloader/downloader.zig");
const types = @import("../index/types/types.zig");
const verity = @import("../security/verify.zig");
const utils = @import("../utils/utils.zig");
const log = @import("../utils/log.zig");

const print = std.debug.print;

// made a function for creating dirs, so if it stalls it only errors the function and not errors pull_repo, messy workaround but wt

fn createdir(io: std.Io, path: []const u8) !void {
    return utils.fs.createdir(io, path);
}


// and another one here, because iof the crossdevice bug
fn rename(io: std.Io, old: []const u8, new: []const u8) !void {
    std.Io.Dir.renameAbsolute(old, new, io) catch |err| switch (err) {
        error.CrossDevice => {
            // rename cannot cross filesystems, so we just stream and delete, also atomic so its better realistically

            const src = try std.Io.Dir.openFileAbsolute(io, old, .{});
            defer src.close(io);

            const dst = try std.Io.Dir.createFileAbsolute(io, new, .{
                .truncate = true,
            });
            defer dst.close(io);

            var writerbuf: [64 * 1024]u8 = undefined;
            var fwriter = dst.writer(io, &writerbuf);
            const writer = &fwriter.interface;

            var buf: [64 * 1024]u8 = undefined;
            var freader = src.reader(io, &buf);
            const reader = &freader.interface;

            while (true) {
                const n = try reader.readSliceShort(&buf);
                

                if (n == 0)
                    break;

                try writer.writeAll(buf[0..n]);
            }
    
            try writer.flush();

            try std.Io.Dir.deleteFileAbsolute(io, old);
        },
        else => return err,
    };
}




// inits the main repo firstly, used in main right after all creations run, this is gonna uhh change, 100% because this is the commit to github
pub fn init_repos(io: std.Io) !void {
    const contents =
        \\[core]
        \\url = "https://github.com/fischblob-lol/xpk-c"
        \\priority = 100
        \\enabled = true
        \\# hello from sundowner (expie)
        \\
    ;
    
    log.warn("first run of xpk may be quite slow due to initalization!\n", .{});

    if (std.Io.Dir.openFileAbsolute(io, globals.reposconf, .{ .mode = .read_only })) |file| {
        file.close(io);
        return;
    } else |err| if (err != error.FileNotFound) return err;

    const file = try std.Io.Dir.createFileAbsolute(io, globals.reposconf, .{ .truncate = false });
    defer file.close(io);

    var writerbuf: [64 * 1024]u8 = undefined;
    
    var fwriter = file.writer(io, &writerbuf);
    const writer = &fwriter.interface;
    
    try writer.writeAll(contents);
    try writer.flush(); 
}

// saves locally, for the repo name inscribed in /opt/xpk/repos/repos.conf (parser work)
// concurrently, and this is just the old renamed torso for pull_repos, this gets a repo handed to it, and downloads it
// so this is also the newer one i made right now in this update,
fn sync_repo(io: std.Io, allocator: std.mem.Allocator, repo: utils.parser.Repo) !void {
    const repopath = try std.fs.path.join(allocator, &.{ globals.local, repo.name });
    defer allocator.free(repopath);

    try createdir(io, repopath);

    
    const indexurl = try std.fmt.allocPrint(allocator, "{s}/index", .{repo.url});
    const keyringurl = try std.fmt.allocPrint(allocator, "{s}/trust/keyring", .{repo.url});
    defer allocator.free(indexurl);
    defer allocator.free(keyringurl);

    log.trace("starting async download\n", .{});
    var indexfut = io.async(downloader.download_repo, .{ io, allocator, indexurl, repo.name, false });
    var keyringfut = io.async(downloader.download, .{ io, allocator, keyringurl, true });

    const downloadedindex = try indexfut.await(io);
    defer allocator.free(downloadedindex);
    const downloadedkeyring = try keyringfut.await(io);
    defer allocator.free(downloadedkeyring);

    const keyringbytes = try std.Io.Dir.cwd().readFileAlloc(io, downloadedkeyring, allocator, .unlimited);
    defer allocator.free(keyringbytes);
    // shan't happen for big repos
    var keyring = utils.parser.parse_k(allocator, keyringbytes) catch |err| {
        log.warn("{s}'s keyring is malformed ({s}), refusing to sync\n", .{ repo.name, @errorName(err) });
        return error.badkeyring;
    };
    defer {
        keyring.maintainers.deinit();
        keyring.helpers.deinit();
    }

    const rawindex = try std.Io.Dir.cwd().readFileAlloc(io, downloadedindex, allocator, .unlimited);
    defer allocator.free(rawindex);

    var signed = types.split_s(rawindex, allocator) catch |err| {
        log.warn("{s}'s index is malformed or unsigned ({s}), refusing to sync\n", .{ repo.name, @errorName(err) });
        return error.badindex;
    };
    defer signed.deinit(allocator);

    verity.verify_s(signed, keyring) catch |err| {
        log.err("{s}'s index failed signature verification ({s}), refusing to sync\n", .{ repo.name, @errorName(err) });
        return error.untrustedindex;
    };

    const indexpath = try std.fs.path.join(allocator, &.{ repopath, "index" });
    const keyringpath = try std.fs.path.join(allocator, &.{ repopath, "keyring" });
    defer allocator.free(indexpath);
    defer allocator.free(keyringpath);

    {
        const file = try std.Io.Dir.createFileAbsolute(io, indexpath, .{ .truncate = true });
        defer file.close(io);
        var writerbuf: [16 * 1024]u8 = undefined;
        var fwriter = file.writer(io, &writerbuf);
        try fwriter.interface.writeAll(signed.body); // unwrapped body, so i dont have to do JACK SHIT for rfetch.zig (luckily)
        try fwriter.interface.flush(); // and thats why the wrapper was my design choice, cuz we can easily just unwrap its shit and put it as a usuable repo
    }

    try rename(io, downloadedkeyring, keyringpath);

    std.Io.Dir.deleteFileAbsolute(io, downloadedindex) catch {};
}

// pulls repos and uses async
pub fn pull_repo(io: std.Io, allocator: std.mem.Allocator) !void {
    const reposbytes = try std.Io.Dir.cwd().readFileAlloc(io, globals.reposconf, allocator, .unlimited);
    defer allocator.free(reposbytes);

    log.info("syncing repos...\n", .{});

    const repos = try utils.parser.parse_r(allocator, reposbytes);
    defer allocator.free(repos);
    
    
    if (repos.len == 0) {
        log.info("no repositories configured, please configure a repo\n", .{});
        return;
    }

    log.trace("setting up async futures\n", .{});
    const Fut = @TypeOf(io.async(sync_repo, .{ io, allocator, repos[0] }));
    var futures: std.ArrayList(Fut) = .empty;
    defer futures.deinit(allocator);

    // keep repo names lined up with futures so we can report which one failed
    var names: std.ArrayList([]const u8) = .empty;
    defer names.deinit(allocator);

    for (repos) |repo| {
        if (!repo.enabled) continue;
        try futures.append(allocator, io.async(sync_repo, .{ io, allocator, repo }));
        try names.append(allocator, repo.name);
    }

    var failures: usize = 0; 

    for (futures.items, 0..) |*futs, i| {
        futs.await(io) catch |err| {
            log.warn("failed to sync {s}: {s}, skipping\n", .{ names.items[i], @errorName(err) });
            failures += 1;
            continue;
        };
    }
    // usually all repos failed to sync means your internet isnt fucking working
    if (failures == futures.items.len and futures.items.len > 0) {
        log.err("all repositories failed to sync, are you sure you are online?\n", .{});
    } else {
        log.success("all repositories up to date!\n", .{});
    }
}

