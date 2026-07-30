const std = @import("std");
const types = @import("../db/types/types.zig");
const db = @import("../db/db.zig");
const globals = @import("../globals.zig");
const parse_r = @import("../parsers/parsers.zig").parse_r;
const log = @import("../utils/log.zig");


// lists all installed packages frommm allllll places
pub fn list(io: std.Io, allocator: std.mem.Allocator) !void {
    log.trace("starting package list operation\n", .{});

    const reposbytes = std.Io.Dir.cwd().readFileAlloc(io, globals.reposconf, allocator, .unlimited) catch |err| {
        log.err("failed reading repos: {s}\n", .{@errorName(err)});
        return err;
    };
    defer allocator.free(reposbytes);

    log.debug1("parsing repository configuration ({d} bytes)\n", .{reposbytes.len});

    const repos = parse_r(allocator, reposbytes) catch |err| {
        log.err("failed parsing repositories: {s}\n", .{@errorName(err)});
        return err;
    };
    defer allocator.free(repos);

    log.debug1("loaded {d} repositories\n", .{repos.len});

    var total: usize = 0;

    for (repos) |repo| {
        log.trace("reading database for repo '{s}'\n", .{repo.name});

        const entries = db.read_w(io, allocator, repo.name) catch |err| {
            log.warn("failed reading database '{s}': {s}\n", .{repo.name, @errorName(err)});
            continue;
        };
        defer allocator.free(entries);

        log.debug2("repo '{s}' contains {d} generation entries\n", .{repo.name, entries.len});

        // dedupe
        var seen: std.StringHashMap(void) = .init(allocator);
        defer seen.deinit();

        var current: std.ArrayList(types.Dbentry) = .empty;
        defer current.deinit(allocator);

        for (entries) |e| {
            if (seen.contains(e.name)) continue;
            try seen.put(e.name, {});

            const active = db.current_e(entries, e.name) orelse continue;
            try current.append(allocator, active);
        }

        if (current.items.len == 0) {
            log.debug3("skipping empty repo '{s}'\n", .{repo.name});
            continue;
        }

        log.info("{s}:\n", .{repo.name});

        for (current.items) |pkg| {
            log.debug3("printing package {s}/{s} (gen {d})\n", .{pkg.category, pkg.name, pkg.generation});

            log.print("  {s}/{s} {s} (gen {d})\n", .{pkg.category, pkg.name, pkg.version, pkg.generation});

            total += 1;
        }

        log.newline("\n");
    }

    log.success("{d} package(s) installed\n", .{total});
}


// searches installed packages, only matches against the currently active generation
pub fn search(io: std.Io, allocator: std.mem.Allocator, query: []const u8) !void {
    log.trace("starting search query '{s}'\n", .{query});

    const reposbytes = std.Io.Dir.cwd().readFileAlloc(io, globals.reposconf, allocator, .unlimited) catch |err| {
        log.err("failed reading repos: {s}\n", .{@errorName(err)});
        return err;
    };
    defer allocator.free(reposbytes);

    const repos = parse_r(allocator, reposbytes) catch |err| {
        log.err("failed parsing repositories: {s}\n", .{@errorName(err)});
        return err;
    };
    defer allocator.free(repos);

    var found: usize = 0;

    for (repos) |repo| {
        log.trace("searching repo '{s}'\n", .{repo.name});

        const entries = db.read_w(io, allocator, repo.name) catch |err| {
            log.warn("failed reading database '{s}': {s}\n", .{repo.name, @errorName(err)});
            continue;
        };
        defer allocator.free(entries);

        var seen: std.StringHashMap(void) = .init(allocator);
        defer seen.deinit();

        for (entries) |e| {
            if (seen.contains(e.name)) continue;
            try seen.put(e.name, {});

            const pkg = db.current_e(entries, e.name) orelse continue;

            log.debug3("checking {s}/{s}\n", .{pkg.category, pkg.name});

            if (std.mem.indexOf(u8, pkg.name, query) != null or
                std.mem.indexOf(u8, pkg.category, query) != null)
            {
                log.info("match found: {s}/{s}\n", .{pkg.category, pkg.name});

                log.print("{s}/{s} {s} ({s}, gen {d})\n", .{pkg.category, pkg.name, pkg.version, pkg.repo, pkg.generation});

                found += 1;
            }
        }
    }

    if (found == 0) {
        log.warn("no packages found matching '{s}'\n", .{query});
        return;
    }

    log.success("{d} package(s) matched\n", .{found});
}


// shows package info, only considers each repo's currently active generation
pub fn info(io: std.Io, allocator: std.mem.Allocator, package: []const u8) !void {
    log.trace("looking up package '{s}'\n", .{package});

    const reposbytes = std.Io.Dir.cwd().readFileAlloc(io, globals.reposconf, allocator, .unlimited) catch |err| {
        log.err("failed reading repos: {s}\n", .{@errorName(err)});
        return err;
    };
    defer allocator.free(reposbytes);

    const repos = parse_r(allocator, reposbytes) catch |err| {
        log.err("failed parsing repositories: {s}\n", .{@errorName(err)});
        return err;
    };
    defer allocator.free(repos);

    var found: ?types.Dbentry = null;
    var foundp: i32 = std.math.minInt(i32);

    for (repos) |repo| {
        log.debug2("checking repo '{s}' priority {d}\n", .{repo.name, repo.priority});

        const entries = db.read_w(io, allocator, repo.name) catch |err| {
            log.warn("failed reading database '{s}': {s}\n", .{
                repo.name,
                @errorName(err),
            });
            continue;
        };
        defer allocator.free(entries);

        const pkg = db.current_e(entries, package) orelse continue;

        log.debug1("found candidate in repo '{s}'\n", .{repo.name});

        if (repo.priority > foundp) {
            log.debug2(
                "repo '{s}' overrides previous candidate\n",
                .{repo.name},
            );

            found = pkg;
            foundp = repo.priority;
        }
    }

    const pkg = found orelse {
        log.warn("{s} is not installed\n", .{package});
        return error.notinstalled;
    };

    log.success("found installed package '{s}'\n", .{pkg.name});

    log.print(
        \\name: {s}
        \\category: {s}
        \\version: {s}
        \\repo: {s}
        \\generation: {d}
        \\objhash: {x}
        \\
    , .{pkg.name, pkg.category, pkg.version, pkg.repo, pkg.generation, pkg.objhash});
}