//! system wide package status for full system rollbacks, not just per package rollbacks
//! decided not to make a types file for this one since everything is 100% exclusively used here for the current moment
//! needs a rework too, suprisngly (in the rollback term) because ANY. Action. makes a systree, not an update nothin just anything, and i have like what? 9 systree from just installing and removing? i need gc to handle these later
//! but otherwise its good
const std = @import("std");
const globals = @import("../globals.zig");
const utils = @import("../utils/utils.zig");
const log = @import("../utils/log.zig");

fn createdir(io: std.Io, path: []const u8) !void {
    return utils.fs.createdir(io, path);
}

const magic = "XPKS";
const formatvers: u16 = 1;

pub const Action = enum(u8) {
    install = 0,
    remove = 1,
    upgrade = 2,
    gc = 3,
    rollback = 4,
};

pub const Logentry = struct {
    systreenum: u32,
    timestamp: i64,
    action: Action,
    pkgname: []const u8,
};

pub const systreeerror = error{ badmagic, unsupportedvers, crcmismatch, truncated };
// boring name, ill remake later
// nope
fn logpath(allocator: std.mem.Allocator) ![]u8 {
    return std.fs.path.join(allocator, &.{ globals.systree, "log" });
}

pub fn read_log(io: std.Io, allocator: std.mem.Allocator) ![]Logentry {
    const path = try logpath(allocator);
    defer allocator.free(path);

    const bytes = std.Io.Dir.cwd().readFileAlloc(io, path, allocator, .unlimited) catch |err| switch (err) {
        error.FileNotFound => return &.{},
        else => return err,
    };
    defer allocator.free(bytes);

    return decode_log(bytes, allocator);
}
// how i feel copy pasting the exact same shit 25 times under a new name
fn decode_log(buf: []const u8, allocator: std.mem.Allocator) ![]Logentry {
    if (buf.len < 4 + 2 + 4 + 4) return systreeerror.truncated;
    if (!std.mem.eql(u8, buf[0..4], magic)) return systreeerror.badmagic;

    var pos: usize = 4;
    const version = std.mem.readInt(u16, buf[pos..][0..2], .little);
    pos += 2;
    if (version != formatvers) return systreeerror.unsupportedvers;

    const count = std.mem.readInt(u32, buf[pos..][0..4], .little);
    pos += 4;

    const storedcrc = std.mem.readInt(u32, buf[buf.len - 4 ..][0..4], .little);
    const expectedcrc = std.hash.Crc32.hash(buf[0 .. buf.len - 4]);
    if (storedcrc != expectedcrc) return systreeerror.crcmismatch;

    const entries = try allocator.alloc(Logentry, count);
    errdefer allocator.free(entries);

    for (entries) |*e| {
        const systreenum = std.mem.readInt(u32, buf[pos..][0..4], .little);
        pos += 4;
        const ts = std.mem.readInt(i64, buf[pos..][0..8], .little);

        pos += 8;
        const action: Action = @enumFromInt(buf[pos]);

        pos += 1;
        const namelen = std.mem.readInt(u16, buf[pos..][0..2], .little);

        pos += 2;
        const pkgname = try allocator.dupe(u8, buf[pos..][0..namelen]);

        pos += namelen;

        e.* = .{ .systreenum = systreenum, .timestamp = ts, .action = action, .pkgname = pkgname };
    }

    return entries;
}
// pretty standrad encoding logic, though im actually having a simmilar problem that i had with my toml parser, its getting too repetitive to write
// genuinely, fucking tired  of writing these. (he wasn't lyin)
fn encode_log(allocator: std.mem.Allocator, entries: []const Logentry) ![]u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(allocator);

    try out.appendSlice(allocator, magic);

    var verbuf: [2]u8 = undefined;
    std.mem.writeInt(u16, &verbuf, formatvers, .little);
    try out.appendSlice(allocator, &verbuf);

    var countbuf: [4]u8 = undefined;
    std.mem.writeInt(u32, &countbuf, @intCast(entries.len), .little);
    try out.appendSlice(allocator, &countbuf);

    for (entries) |e| {
        var numbuf: [4]u8 = undefined;
        std.mem.writeInt(u32, &numbuf, e.systreenum, .little);
        try out.appendSlice(allocator, &numbuf);

        var tsbuf: [8]u8 = undefined;
        std.mem.writeInt(i64, &tsbuf, e.timestamp, .little);
        try out.appendSlice(allocator, &tsbuf);

        try out.append(allocator, @intFromEnum(e.action));

        var namelenbuf: [2]u8 = undefined;
        std.mem.writeInt(u16, &namelenbuf, @intCast(e.pkgname.len), .little);
        try out.appendSlice(allocator, &namelenbuf);
        try out.appendSlice(allocator, e.pkgname);
    }

    const crc = std.hash.Crc32.hash(out.items);
    var crcbuf: [4]u8 = undefined;
    std.mem.writeInt(u32, &crcbuf, crc, .little);
    try out.appendSlice(allocator, &crcbuf);

    return out.toOwnedSlice(allocator);
}

fn write_log(io: std.Io, allocator: std.mem.Allocator, entries: []const Logentry) !void {
    const path = try logpath(allocator);
    defer allocator.free(path);

    const encoded = try encode_log(allocator, entries);
    defer allocator.free(encoded);

    const file = try std.Io.Dir.createFileAbsolute(io, path, .{ .truncate = true });
    defer file.close(io);

    var writerbuf: [16 * 1024]u8 = undefined;
    var fwriter = file.writer(io, &writerbuf);
    try fwriter.interface.writeAll(encoded);
    try fwriter.interface.flush();
}

fn latest_systree(io: std.Io, allocator: std.mem.Allocator) !u32 {
    var dir = std.Io.Dir.openDirAbsolute(io, globals.systree, .{ .iterate = true }) catch |err| switch (err) {
        error.FileNotFound => return 0,
        else => return err,
    };
    defer dir.close(io);

    var best: u32 = 0;
    var found = false;

    var it = dir.iterate();
    while (try it.next(io)) |entry| {
        if (entry.kind != .directory) continue;
        if (!std.mem.startsWith(u8, entry.name, "systree-")) continue;

        const num = std.fmt.parseInt(u32, entry.name["systree-".len..], 10) catch continue;
        if (!found or num > best) {
            best = num;
            found = true;
        }
    }
    _ = allocator;

    return if (found) best else 0;
}

pub fn systree_path(allocator: std.mem.Allocator, num: u32) ![]u8 {
    var numbuf: [10]u8 = undefined;
    const numstr = try std.fmt.bufPrint(&numbuf, "systree-{d}", .{num});
    return std.fs.path.join(allocator, &.{ globals.systree, numstr });
}
// cool ass name tho
pub fn seal_systree(io: std.Io, allocator: std.mem.Allocator, pkgname: []const u8, action: Action) !void {
    try createdir(io, globals.systree);

    const last = try latest_systree(io, allocator);
    const nextnum = last + 1;

    const dest = try systree_path(allocator, nextnum);
    defer allocator.free(dest);

    const tmppath = try std.fmt.allocPrint(allocator, "{s}.tmp-{d}", .{ dest, std.Io.Timestamp.now(io, .real).toSeconds() });
    defer allocator.free(tmppath);

    try createdir(io, tmppath);

    var currentdir = try std.Io.Dir.openDirAbsolute(io, globals.current, .{ .iterate = true });
    defer currentdir.close(io);

    var repoit = currentdir.iterate();
    while (try repoit.next(io)) |repoentry| {
        if (repoentry.kind != .directory) continue;

        const repopath = try std.fs.path.join(allocator, &.{ globals.current, repoentry.name });
        defer allocator.free(repopath);

        var repodir = try std.Io.Dir.openDirAbsolute(io, repopath, .{ .iterate = true });
        defer repodir.close(io);

        const systreerepodir = try std.fs.path.join(allocator, &.{ tmppath, repoentry.name });
        defer allocator.free(systreerepodir);
        try createdir(io, systreerepodir);

        var pkgit = repodir.iterate();
        while (try pkgit.next(io)) |pkgentry| {
            if (pkgentry.kind != .sym_link) continue;

            const linkpath = try std.fs.path.join(allocator, &.{ repopath, pkgentry.name });
            defer allocator.free(linkpath);

            var buf: [std.fs.max_path_bytes]u8 = undefined;
            const len = try std.Io.Dir.readLinkAbsolute(io, linkpath, &buf);
            const target = buf[0..len];

            const snappath = try std.fs.path.join(allocator, &.{ systreerepodir, pkgentry.name });
            defer allocator.free(snappath);

            try std.Io.Dir.symLinkAbsolute(io, target, snappath, .{});
        }
    }

    try std.Io.Dir.renameAbsolute(tmppath, dest, io);

    const log_entries = try read_log(io, allocator);
    defer {
        for (log_entries) |e| allocator.free(e.pkgname);
        allocator.free(log_entries);
    }

    var list: std.ArrayList(Logentry) = .empty;
    defer list.deinit(allocator);
    try list.appendSlice(allocator, log_entries);
    try list.append(allocator, .{
        .systreenum = nextnum,
        .timestamp = std.Io.Timestamp.now(io, .real).toSeconds(),
        .action = action,
        .pkgname = pkgname,
    });

    try write_log(io, allocator, list.items);

    log.debug1("sealed systree-{d}\n", .{nextnum});
}

pub fn revert_systree(io: std.Io, allocator: std.mem.Allocator, num: u32) !void {
    const src = try systree_path(allocator, num);
    defer allocator.free(src);

    var systreedir = std.Io.Dir.openDirAbsolute(io, src, .{ .iterate = true }) catch |err| switch (err) {
        error.FileNotFound => {
            log.err("systree-{d} doesn't exist\n", .{num});
            return error.systreenotfound;
        },
        else => return err,
    };
    defer systreedir.close(io);

    var repoit = systreedir.iterate();
    while (try repoit.next(io)) |repoentry| {
        if (repoentry.kind != .directory) continue;

        const systreerepopath = try std.fs.path.join(allocator, &.{ src, repoentry.name });
        defer allocator.free(systreerepopath);

        var systreerepodir = try std.Io.Dir.openDirAbsolute(io, systreerepopath, .{ .iterate = true });
        defer systreerepodir.close(io);

        const currentrepodir = try std.fs.path.join(allocator, &.{ globals.current, repoentry.name });
        defer allocator.free(currentrepodir);
        try createdir(io, currentrepodir);

        var pkgit = systreerepodir.iterate();
        while (try pkgit.next(io)) |pkgentry| {
            if (pkgentry.kind != .sym_link) continue;

            const systreelinkpath = try std.fs.path.join(allocator, &.{ systreerepopath, pkgentry.name });
            defer allocator.free(systreelinkpath);

            var buf: [std.fs.max_path_bytes]u8 = undefined;
            const len = try std.Io.Dir.readLinkAbsolute(io, systreelinkpath, &buf);
            const target = buf[0..len];

            const currentlinkpath = try std.fs.path.join(allocator, &.{ currentrepodir, pkgentry.name });
            defer allocator.free(currentlinkpath);

            const tmppath = try std.fmt.allocPrint(allocator, "{s}.tmp-{d}", .{ currentlinkpath, std.Io.Timestamp.now(io, .real).toSeconds() });
            defer allocator.free(tmppath);

            std.Io.Dir.deleteFileAbsolute(io, tmppath) catch |err| switch (err) {
                error.FileNotFound => {},
                else => return err,
            };

            try std.Io.Dir.symLinkAbsolute(io, target, tmppath, .{});
            try std.Io.Dir.renameAbsolute(tmppath, currentlinkpath, io);
        }
    }

    log.success("reverted to systree-{d}\n", .{num});
}
// formatter, will move this to misc too cuz our db's contain time
fn formatt(buf: []u8, timestamp: i64) ![]u8 {
    const epochseconds: std.time.epoch.EpochSeconds = .{ .secs = @intCast(timestamp) };
    const daysec = epochseconds.getDaySeconds();
    const epochday = epochseconds.getEpochDay();
    const yearday = epochday.calculateYearDay();
    const monthday = yearday.calculateMonthDay();

    return std.fmt.bufPrint(buf, "{d}-{d:0>2}-{d:0>2} {d:0>2}:{d:0>2}:{d:0>2}", .{
        yearday.year,
        monthday.month.numeric(),
        monthday.day_index + 1,
        daysec.getHoursIntoDay(),
        daysec.getMinutesIntoHour(),
        daysec.getSecondsIntoMinute(),
    });
}
pub fn history(io: std.Io, allocator: std.mem.Allocator) !void {
    const entries = try read_log(io, allocator);
    defer {
        for (entries) |e| allocator.free(e.pkgname);
        allocator.free(entries);
    }

    if (entries.len == 0) {
        log.info("no systree sealed yet\n", .{});
        return;
    }
    // is for later
    for (entries) |e| {
        const actionstr = switch (e.action) {
            .install => "installed",
            .remove => "removed",
            .upgrade => "upgraded",
            .gc => "gc'd",
            .rollback => "rolled back",
        };

        var tsbuf: [32]u8 = undefined;
        const tsstr = try formatt(&tsbuf, e.timestamp);

        log.print("systree-{d}  {s}  {s} {s}\n", .{ e.systreenum, tsstr, actionstr, e.pkgname });
    }
}

