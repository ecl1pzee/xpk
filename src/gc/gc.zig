//! the garbage collection system
// now better!
const std = @import("std");
const globals = @import("../globals.zig");
const db = @import("../db/db.zig");
const snapshots = @import("../db/snapshots.zig");
const utils = @import("../utils/utils.zig");
const log = @import("../utils/log.zig");
const config = @import("../config.zig");
const Hashset = std.AutoHashMap([32]u8, void);

fn read_repos(io: std.Io, allocator: std.mem.Allocator) ![]utils.parser.Repo {
    const reposbytes = try std.Io.Dir.cwd().readFileAlloc(io, globals.reposconf, allocator, .unlimited);
    defer allocator.free(reposbytes);
    return utils.parser.parse_r(allocator, reposbytes);
}

fn current_genof(io: std.Io, allocator: std.mem.Allocator, reponame: []const u8, pkgname: []const u8) !?u32 {
    const linkpath = try snapshots.current_path(allocator, reponame, pkgname);
    defer allocator.free(linkpath);

    var buf: [std.fs.max_path_bytes]u8 = undefined;
    const len = std.Io.Dir.readLinkAbsolute(io, linkpath, &buf) catch |err| switch (err) {
        error.FileNotFound => return null,
        else => return err,
    };
    const target = buf[0..len];

    var base = std.fs.path.basename(target);
    // should prob make layer- a global variable for future renaming (if we do)
    if (std.mem.startsWith(u8, base, "layer-")) base = base["layer-".len..];

    return std.fmt.parseInt(u32, base, 10) catch null;
}
// didn't touch sorting in a while
fn list_diskong(io: std.Io, allocator: std.mem.Allocator, reponame: []const u8, pkgname: []const u8) ![]u32 {
    const pkgdir = try std.fs.path.join(allocator, &.{ globals.snapshots, reponame, pkgname });
    defer allocator.free(pkgdir);

    var gens: std.ArrayList(u32) = .empty;
    errdefer gens.deinit(allocator);

    var dir = std.Io.Dir.openDirAbsolute(io, pkgdir, .{ .iterate = true }) catch |err| switch (err) {
        error.FileNotFound => return gens.toOwnedSlice(allocator),
        else => return err,
    };
    defer dir.close(io);

    var it = dir.iterate();
    while (try it.next(io)) |entry| {
        if (entry.kind != .directory) continue;
        if (!std.mem.startsWith(u8, entry.name, "layer-")) continue;

        const num = std.fmt.parseInt(u32, entry.name["layer-".len..], 10) catch continue;
        try gens.append(allocator, num);
    }

    std.mem.sort(u32, gens.items, {}, struct {
        fn greater(_: void, a: u32, b: u32) bool {
            return a > b;
        }
    }.greater);

    return gens.toOwnedSlice(allocator);
}

fn list_ondiskpkgs(io: std.Io, allocator: std.mem.Allocator, reponame: []const u8) ![][]const u8 {
    const repodir = try std.fs.path.join(allocator, &.{ globals.snapshots, reponame });
    defer allocator.free(repodir);

    var pkgs: std.ArrayList([]const u8) = .empty;
    errdefer {
        for (pkgs.items) |p| allocator.free(p);
        pkgs.deinit(allocator);
    }

    var dir = std.Io.Dir.openDirAbsolute(io, repodir, .{ .iterate = true }) catch |err| switch (err) {
        error.FileNotFound => return pkgs.toOwnedSlice(allocator),
        else => return err,
    };
    defer dir.close(io);

    var it = dir.iterate();
    while (try it.next(io)) |entry| {
        if (entry.kind != .directory) continue;
        try pkgs.append(allocator, try allocator.dupe(u8, entry.name));
    }

    return pkgs.toOwnedSlice(allocator);
}

fn prune_pkg(io: std.Io, allocator: std.mem.Allocator, reponame: []const u8, pkgname: []const u8, keep: u32) !usize {
    const ondiskgens = try list_diskong(io, allocator, reponame, pkgname);
    defer allocator.free(ondiskgens);

    if (ondiskgens.len == 0) return 0;

    const activegen = try current_genof(io, allocator, reponame, pkgname);

    var removedcount: usize = 0;
    var keptcount: usize = 0;

    for (ondiskgens) |gen| {
        const isactive = activegen != null and gen == activegen.?;

        if (isactive) {
            keptcount += 1;
            log.debug2("keeping {s}/{s} generation {d} (active, symlinked)\n", .{ reponame, pkgname, gen });
            continue;
        }

        if (keptcount < keep) {
            keptcount += 1;
            log.debug2("keeping {s}/{s} generation {d} (within keep window, {d}/{d})\n", .{ reponame, pkgname, gen, keptcount, keep });
            continue;
        }

        const gendir = try snapshots.generation_path(allocator, reponame, pkgname, gen);
        defer allocator.free(gendir);

        snapshots.remove_generation(io, gendir) catch |err| switch (err) {
            error.FileNotFound => {},
            else => {
                log.warn("failed removing generation {d} of {s}: {s}\n", .{ gen, pkgname, @errorName(err) });
                continue;
            },
        };

        log.debug1("pruned {s}/{s} generation {d}\n", .{ reponame, pkgname, gen });
        removedcount += 1;
    }

    return removedcount;
}

fn reconcile_world(io: std.Io, allocator: std.mem.Allocator, reponame: []const u8) !void {
    const entries = try db.read_w(io, allocator, reponame);
    defer allocator.free(entries);

    var kept: std.ArrayList(db.Dbentry) = .empty;
    defer kept.deinit(allocator);

    var cache: std.StringHashMap([]u32) = .init(allocator);
    defer {
        var it = cache.valueIterator();
        while (it.next()) |v| allocator.free(v.*);
        cache.deinit();
    }

    for (entries) |e| {
        const gop = try cache.getOrPut(e.name);
        if (!gop.found_existing) {
            gop.value_ptr.* = try list_diskong(io, allocator, reponame, e.name);
        }

        const stillondisk = for (gop.value_ptr.*) |g| {
            if (g == e.generation) break true;
        } else false;

        if (stillondisk) try kept.append(allocator, e);
    }

    try db.write_w(io, allocator, reponame, kept.items);
}

// new, marks all trees if file or a dir, recursive
fn mark_alltrees(io: std.Io, allocator: std.mem.Allocator, roothash: [32]u8, livetrees: *Hashset, livecontent: *Hashset) !void {
    try livetrees.put(roothash, {});

    var loaded = try snapshots.load_tree(io, allocator, roothash);
    defer loaded.deinit(allocator);

    for (loaded.entries) |e| {
        switch (e.kind) {
            .file => try livecontent.put(e.hash, {}),
            .dir => try mark_alltrees(io, allocator, e.hash, livetrees, livecontent),
        }
    }
}

fn collect_live(io: std.Io, allocator: std.mem.Allocator, repos: []const utils.parser.Repo, livetrees: *Hashset, livecontent: *Hashset) !void {
    for (repos) |repo| {
        if (repo.name.len == 0) continue;

        const pkgs = list_ondiskpkgs(io, allocator, repo.name) catch |err| {
            log.warn("failed listing snapshots packages for '{s}': {s}\n", .{ repo.name, @errorName(err) });
            continue;
        };
        defer {
            for (pkgs) |p| allocator.free(p);
            allocator.free(pkgs);
        }

        for (pkgs) |pkgname| {
            const gens = list_diskong(io, allocator, repo.name, pkgname) catch |err| {
                log.warn("failed listing generations for '{s}/{s}': {s}\n", .{ repo.name, pkgname, @errorName(err) });
                continue;
            };
            defer allocator.free(gens);

            for (gens) |gen| {
                try mark_genlive(io, allocator, repo.name, pkgname, gen, livetrees, livecontent);
            }
        }
    }
}

fn mark_genlive(io: std.Io, allocator: std.mem.Allocator, reponame: []const u8, pkgname: []const u8, gen: u32, livetrees: *Hashset, livecontent: *Hashset) !void {
    const gendir = try snapshots.generation_path(allocator, reponame, pkgname, gen);
    defer allocator.free(gendir);

    const markerpath = try std.fs.path.join(allocator, &.{ gendir, snapshots.treehashm });
    defer allocator.free(markerpath);

    // hex
    const hex = std.Io.Dir.cwd().readFileAlloc(io, markerpath, allocator, .limited(256)) catch |err| switch (err) {
        error.FileNotFound => return,
        else => {
            log.warn("failed reading treehash marker {s}: {s}\n", .{ markerpath, @errorName(err) });
            return;
        },
    };
    defer allocator.free(hex);

    var hash: [32]u8 = undefined;
    _ = std.fmt.hexToBytes(&hash, std.mem.trim(u8, hex, " \n\r\t")) catch return;
    // added this shit here, and decided to fledge out in erroring in files, later on ill replace every single 'try' call with a catch (a goal)
    mark_alltrees(io, allocator, hash, livetrees, livecontent) catch |err| {
        log.warn("failed walking tree for {s}/{s} gen {d}: {s}\n", .{ reponame, pkgname, gen, @errorName(err) });
    };
}
// looks at dir, and sweeps it, simple.
// does 99% of the work
fn sweep_dir(io: std.Io, allocator: std.mem.Allocator, root: []const u8, live: *const Hashset) !usize {
    var removedcount: usize = 0;

    var dir = std.Io.Dir.openDirAbsolute(io, root, .{ .iterate = true }) catch |err| switch (err) {
        error.FileNotFound => return 0,
        else => return err,
    };
    defer dir.close(io);

    var shardit = dir.iterate();
    while (try shardit.next(io)) |shard| {
        if (shard.kind != .directory) continue;

        const shardpath = try std.fs.path.join(allocator, &.{ root, shard.name });
        defer allocator.free(shardpath);

        var emptied = true;

        {
            var sharddir = try std.Io.Dir.openDirAbsolute(io, shardpath, .{ .iterate = true });
            defer sharddir.close(io);

            var fileit = sharddir.iterate();
            while (try fileit.next(io)) |file| {
                if (file.kind != .file) continue;

                const fullhex = try std.fmt.allocPrint(allocator, "{s}{s}", .{ shard.name, file.name });
                defer allocator.free(fullhex);

                if (fullhex.len != 64) {
                    emptied = false;
                    continue;
                }

                var hash: [32]u8 = undefined;
                _ = std.fmt.hexToBytes(&hash, fullhex) catch {
                    emptied = false;
                    continue;
                };

                if (live.contains(hash)) {
                    emptied = false;
                    continue;
                }

                const filepath = try std.fs.path.join(allocator, &.{ shardpath, file.name });
                defer allocator.free(filepath);

                std.Io.Dir.deleteFileAbsolute(io, filepath) catch |err| {
                    log.warn("failed deleting orphaned object {s}: {s}\n", .{ filepath, @errorName(err) });
                    emptied = false;
                    continue;
                };

                log.debug2("swept orphaned object {s}\n", .{fullhex});
                removedcount += 1;
            }
        }

        if (emptied) {
            dir.deleteDir(io, shard.name) catch |err| switch (err) {
                error.FileNotFound, error.DirNotEmpty => {},
                else => log.warn("failed removing empty shard {s}: {s}\n", .{ shardpath, @errorName(err) }),
            };
        }
    }

    return removedcount;
}
// literally remains the same
pub fn run(io: std.Io, allocator: std.mem.Allocator, keep: u32) !void {
    log.info("starting garbage collection, keeping {d} generation(s) per package\n", .{keep});

    const repos = try read_repos(io, allocator);
    defer allocator.free(repos);

    var prunedtotal: usize = 0;
    for (repos) |repo| {
        if (repo.name.len == 0) continue;

        const pkgs = list_ondiskpkgs(io, allocator, repo.name) catch |err| {
            log.warn("failed listing snapshots packages for '{s}': {s}\n", .{ repo.name, @errorName(err) });
            continue;
        };
        defer {
            for (pkgs) |p| allocator.free(p);
            allocator.free(pkgs);
        }

        for (pkgs) |pkgname| {
            const pruned = prune_pkg(io, allocator, repo.name, pkgname, keep) catch |err| {
                log.warn("failed pruning {s}/{s}: {s}\n", .{ repo.name, pkgname, @errorName(err) });
                continue;
            };
            prunedtotal += pruned;
        }

        reconcile_world(io, allocator, repo.name) catch |err| {
            log.warn("failed reconciling world db for '{s}': {s}\n", .{ repo.name, @errorName(err) });
        };
    }

    log.info("pruned {d} old generation(s), sweeping unreferenced snapshots...\n", .{prunedtotal});

    var livetrees: Hashset = .init(allocator);
    defer livetrees.deinit();

    var livecontent: Hashset = .init(allocator);
    defer livecontent.deinit();

    try collect_live(io, allocator, repos, &livetrees, &livecontent);

    const contentroot = try std.fs.path.join(allocator, &.{ globals.objects, "content" });
    defer allocator.free(contentroot);

    const treesroot = try std.fs.path.join(allocator, &.{ globals.objects, "trees" });
    defer allocator.free(treesroot);

    const sweptcontent = try sweep_dir(io, allocator, contentroot, &livecontent);

    const sweptrees = try sweep_dir(io, allocator, treesroot, &livetrees);

    log.success("gc complete: pruned {d} generation(s), swept {d} content object(s), {d} tree object(s)\n", .{ prunedtotal, sweptcontent, sweptrees });
}