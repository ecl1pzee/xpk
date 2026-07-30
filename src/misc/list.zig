const std = @import("std");
const types = @import("../db/types/types.zig");
const db = @import("../db/db.zig");
const globals = @import("../globals.zig");
const parse_r = @import("../parsers/parsers.zig").parse_r;

const print = std.debug.print;

inline fn iprint(comptime fmt: []const u8, args: anytype) void {
    print("[*] " ++ fmt, args);
}

inline fn wprint(comptime fmt: []const u8, args: anytype) void {
    print("[!] " ++ fmt, args);
}


// lists all installed packages frommm allllll places
pub fn list(io: std.Io, allocator: std.mem.Allocator) !void {
    const reposbytes = std.Io.Dir.cwd().readFileAlloc(io, globals.reposconf, allocator, .unlimited) catch |err| {
        wprint("failed reading repos: {s}\n", .{@errorName(err)}); // gotta start spamming errorname more since it looks good 
        return err;
    };
    defer allocator.free(reposbytes);

    const repos = try parse_r(allocator, reposbytes);
    defer allocator.free(repos);

    var total: usize = 0;

    for (repos) |repo| {
        const entries = try db.read_w(io, allocator, repo.name);
        defer allocator.free(entries);

        if (entries.len == 0)
            continue;

        print("{s}:\n", .{repo.name});
        
        for (entries) |pkg| {
            print(
                "  {s}/{s} {s}\n",
                .{
                    pkg.category,
                    pkg.name,
                    pkg.version,
                },
            );

            total += 1;
        }

        print("\n", .{});
    }

    iprint("{d} package(s) installed\n", .{total});
}


// searches installed packages MEYWORD INSTALLED, ill move this to info later tho
pub fn search(io: std.Io, allocator: std.mem.Allocator,query: []const u8) !void {
    const reposbytes = try std.Io.Dir.cwd().readFileAlloc(io,globals.reposconf, allocator, .unlimited);
    defer allocator.free(reposbytes);

    const repos = try parse_r(allocator, reposbytes);
    defer allocator.free(repos);

    var found: usize = 0;

    for (repos) |repo| {
        const entries = try db.read_w(io, allocator, repo.name);
        defer allocator.free(entries);

        for (entries) |pkg| {
            if (std.mem.indexOf(u8, pkg.name, query) != null or
                std.mem.indexOf(u8, pkg.category, query) != null)
            {
                print("{s}/{s} {s} ({s})\n",.{pkg.category,pkg.name,pkg.version,pkg.repo});
                found += 1;
            }
        }
    }

    if (found == 0) {
        wprint("no packages found matching '{s}'\n", .{query});
    }
}


// shows package info
pub fn info(io: std.Io, allocator: std.mem.Allocator, package: []const u8) !void {
    const reposbytes = std.Io.Dir.cwd().readFileAlloc(io, globals.reposconf, allocator, .unlimited) catch |err| {
        wprint("failed reading repos: {s}\n", .{@errorName(err)});
        return err;
    };
    defer allocator.free(reposbytes);

    const repos = try parse_r(allocator, reposbytes);
    defer allocator.free(repos);

    var found: ?types.Dbentry = null;
    var foundp: i32 = std.math.minInt(i32);

    for (repos) |repo| {
        const entries = try db.read_w(io, allocator, repo.name);
        defer allocator.free(entries);

        for (entries) |pkg| {
            if (!std.mem.eql(u8, pkg.name, package))
                continue;

            if (repo.priority > foundp) {
                found = pkg;
                foundp = repo.priority;
            }
        }
    }

    const pkg = found orelse {
        wprint("{s} is not installed\n", .{package});
        return error.notinstalled;
    };
    
    print(
        \\name: {s}
        \\category: {s}
        \\version: {s}
        \\repo: {s}
        \\
    ,.{pkg.name,pkg.category,pkg.version,pkg.repo});
}