//! removal: unlinks a package's symlinks from globals.base, deletes its shit. easy.
//! rewritten for new ostree approach
//! added better unlinking that doesn't rehash the entire shit, which was actually gonna be really performance heavy later on
const std = @import("std");
const globals = @import("../globals.zig");
const db = @import("../db/db.zig");
const strata = @import("../db/strata.zig");
const utils = @import("../utils/utils.zig");
const log = @import("../utils/log.zig");
const stratum = @import("../stratum/stratum.zig");
pub const Removeerror = error{notinstalled};

const Owner = struct {
    repo: utils.parser.Repo,
    entry: db.Dbentry,
};

fn find_owner(io: std.Io, allocator: std.mem.Allocator, repos: []const utils.parser.Repo, name: []const u8) !?Owner {
    var found: ?Owner = null;
    var foundp: i32 = std.math.minInt(i32);

    for (repos) |repo| {
        const entries = db.read_w(io, allocator, repo.name) catch |err| {
            log.warn("failed reading database '{s}': {s}\n", .{ repo.name, @errorName(err) });
            continue;
        };
        defer allocator.free(entries);

        const entry = db.current_e(entries, name) orelse continue;

        if (repo.priority > foundp) {
            found = .{ .repo = repo, .entry = entry };
            foundp = repo.priority;
        }
    }

    return found;
}

const Unlinkctx = struct {
    io: std.Io,
};
// you might be wondering: why discsrd hash? well we need to, unused variable issues (we don't actually USE everything)
// but anyways right, its a newer n better design.
fn unlink_cb(allocator: std.mem.Allocator, crel: []const u8, hash: [32]u8, mode: u32, ctx: *anyopaque) anyerror!void {
    _ = hash;
    _ = mode;
    const c: *Unlinkctx = @ptrCast(@alignCast(ctx));

    const linkpath = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ globals.base, crel });
    defer allocator.free(linkpath);

    std.Io.Dir.deleteFileAbsolute(c.io, linkpath) catch |err| switch (err) {
        error.FileNotFound => {
            log.warn("{s} was already missing, skipping\n", .{linkpath});
        },
        else => return err,
    };

    log.debug2("unlinked {s}\n", .{linkpath});
}

fn unlink_paths(io: std.Io, allocator: std.mem.Allocator, roothash: [32]u8) !void {
    var ctx = Unlinkctx{ .io = io };
    try strata.walk_tree(io, allocator, roothash, "", unlink_cb, @ptrCast(&ctx));
}

fn unlink_current(io: std.Io, allocator: std.mem.Allocator, reponame: []const u8, pkgname: []const u8) !void {
    const linkpath = try strata.current_path(allocator, reponame, pkgname);
    defer allocator.free(linkpath);

    std.Io.Dir.deleteFileAbsolute(io, linkpath) catch |err| switch (err) {
        error.FileNotFound => {
            log.warn("{s} was already missing, skipping\n", .{linkpath});
        },
        else => return err,
    };

    log.debug2("unlinked {s}\n", .{linkpath});
}

fn remove_stratadirs(io: std.Io, allocator: std.mem.Allocator, reponame: []const u8, pkgname: []const u8) !void {
    const pkgdir = try std.fs.path.join(allocator, &.{ globals.strata, reponame, pkgname });
    defer allocator.free(pkgdir);

    var parent = std.Io.Dir.openDirAbsolute(io, std.fs.path.dirname(pkgdir) orelse return, .{}) catch |err| switch (err) {
        error.FileNotFound => return,
        else => return err,
    };
    defer parent.close(io);

    parent.deleteTree(io, pkgname) catch |err| {
        log.warn("failed removing strata dir for {s}/{s}: {s}\n", .{ reponame, pkgname, @errorName(err) });
        return err;
    };

    log.debug1("removed strata directory for {s}/{s}\n", .{ reponame, pkgname });
}

pub fn remove(io: std.Io, allocator: std.mem.Allocator, pkgname: []const u8) !void {
    log.trace("starting removal of {s}\n", .{pkgname});

    const reposbytes = try std.Io.Dir.cwd().readFileAlloc(io, globals.reposconf, allocator, .unlimited);
    defer allocator.free(reposbytes);

    const repos = try utils.parser.parse_r(allocator, reposbytes);
    defer allocator.free(repos);

    const owner = try find_owner(io, allocator, repos, pkgname) orelse {
        log.warn("{s} is not installed\n", .{pkgname});
        return Removeerror.notinstalled;
    };

    log.debug1("{s} is owned by repo '{s}'\n", .{ pkgname, owner.repo.name });

    log.info("unlinking merged paths\n", .{});
    try unlink_paths(io, allocator, owner.entry.objhash);

    log.debug1("releasing ownership records\n", .{});
    try strata.release_ownership(io, allocator, owner.repo.name, pkgname);

    log.info("unlinking current generation\n", .{});
    try unlink_current(io, allocator, owner.repo.name, pkgname);

    log.info("removing strata generations\n", .{});
    try remove_stratadirs(io, allocator, owner.repo.name, pkgname);

    try db.remove_i(io, allocator, owner.repo.name, pkgname);

    log.debug2("sealing stratum\n", .{});
    try stratum.seal_stratum(io, allocator, pkgname, .remove);

    log.success("removed {s}\n", .{pkgname});
}