const std = @import("std");
const types = @import("types/types.zig");
const log = @import("../utils/log.zig");
const automl = @import("automl");

const print = std.debug.print;

// so, congrats to me! i've written an entire fucking fully function toml parser, and its working here as evident

// instead of a shitty 150 line parser my parser is now 1000 lines and is a helper!
// rewritten entirely.

// helpers

pub fn get_str_dup(doc: *automl.Document, section: []const u8, key: []const u8, allocator: std.mem.Allocator) !?[]const u8 {
    if (try doc.get_str(section, key)) |s| {
        return try allocator.dupe(u8, s);
    }
    return null;
}

pub fn get_strarr_dup_or_empty(doc: *automl.Document, section: []const u8, key: []const u8, allocator: std.mem.Allocator) ![]const []const u8 {
    if (try doc.get_strarr(section, key, allocator)) |arr| {
        var duped = try allocator.alloc([]const u8, arr.len);
        for (arr, 0..) |s, i| {
            duped[i] = try allocator.dupe(u8, s);
        }
        return duped;
    }
    return &[_][]const u8{};
}
// helpers end

// entirelyrewritten, every function. 
// because of automl string dedups.

pub fn parse_k(allocator: std.mem.Allocator, text: []const u8) !types.Keyring {
    var parser = automl.Parser.init(allocator);
    var doc = parser.parse(text) catch |err| {
        log.err("{f}\n", .{parser.diag});
        return err;
    };
    defer doc.deinit();

    var result: types.Keyring = .{
        .maintainers = std.StringHashMap(types.Key).init(allocator),
        .helpers = std.StringHashMap(types.Key).init(allocator),
    };

    result.requiredsigs = @intCast(try doc.get_int("policy", "required-signatures") orelse return error.missingkeys);
    result.allowhelpers = try doc.get_bool("policy", "allow-helpers") orelse false;

    var foundkeys = false;

    if (doc.children("maintainers")) |*maintainers| {
        var it = maintainers.*;
        while (it.next()) |entry| {
            // pass entry.value_ptr.values instead of entry.value_ptr, that was fix for my new automl shit
            const key_dup = try allocator.dupe(u8, entry.key_ptr.*);
            errdefer allocator.free(key_dup);
            try result.maintainers.put(key_dup, try key_ftb(allocator, &entry.value_ptr.values));
            foundkeys = true;
        }
    }

    if (doc.children("helpers")) |*helpers| {
        var it = helpers.*;
        while (it.next()) |entry| {
            const key_dup = try allocator.dupe(u8, entry.key_ptr.*);
            errdefer allocator.free(key_dup);
            try result.helpers.put(key_dup, try key_ftb(allocator, &entry.value_ptr.values));
            foundkeys = true;
        }
    }

    if (!foundkeys)
        return error.missingkeys;

    return result;
}

// pulls fields from there, key_fromtable, required for children
fn key_ftb(allocator: std.mem.Allocator, table: *automl.Table) !types.Key {
    const fp = (table.get("fingerprint") orelse return error.unknownkeyinkeyring).as_str() orelse return error.unknownkeyinkeyring;
    var key: types.Key = .{
        .fingerprint = try allocator.dupe(u8, fp),
        .added = "",
        .active = false,
        .revoked = false,
    };
    if (table.get("added")) |v| {
        if (v.as_str()) |s| key.added = try allocator.dupe(u8, s);
    }
    if (table.get("active")) |v| {
        if (v.as_bool()) |b| key.active = b;
    }
    if (table.get("revoked")) |v| {
        if (v.as_bool()) |b| key.revoked = b;
    }
    return key;
}



pub fn parse_r(allocator: std.mem.Allocator, text: []const u8) ![]types.Repo {
    var parser = automl.Parser.init(allocator);
    var doc = parser.parse(text) catch |err| {
        log.err("{f}\n", .{parser.diag});
        return err;
    };
    defer doc.deinit();

    var repos: std.ArrayList(types.Repo) = .empty;
    errdefer {
        // free every url already appended before whatever error tripped us up 
        for (repos.items) |repo| allocator.free(repo.url);
        repos.deinit(allocator);
    }

    var sections = doc.sections.iterator(); // sections is a field (StringHashMap), not a method
    while (sections.next()) |entry| {
        const name = entry.key_ptr.*;
        const sect = entry.value_ptr; // section

        const rawurl = sect.values.get("url") orelse return error.missingurl;
        const urlstr = rawurl.as_str() orelse return error.missingurl;

        var url: []const u8 = undefined;
        if (std.mem.indexOf(u8, urlstr, "codeberg") != null) {
            // for codeberg or foirjo i forgot the name
            url = try std.fmt.allocPrint(allocator, "{s}/raw", .{urlstr});
        } else if (std.mem.indexOf(u8, urlstr, "github") != null) {
            // for github
            url = try std.fmt.allocPrint(allocator, "{s}/raw/main", .{urlstr});
        } else {
            // case of unknown host, will work if the layout is cool but ill add more checks n shit
            url = try allocator.dupe(u8, urlstr);
        }
        // into repos, so it needs its own cleanup on that path specifically
        errdefer allocator.free(url); // so thats why its here

        const priority: u8 = if (sect.values.get("priority")) |v| 
            @intCast(v.as_int() orelse return error.invalidpriority)
        else
            0;

        const enabled: bool = if (sect.values.get("enabled")) |v|
            v.as_bool() orelse return error.invalidbool
        else
            true;

        try repos.append(allocator, .{
            .name = try allocator.dupe(u8, name), // fix for shitty problem i had w my gc
            // also said problem probably causes a veery veryy small memory leak, and if we want to fix it we should free it everywhere. FUCK. ill add a fix later, if thats even the case
            .url = url,
            .priority = priority,
            .enabled = enabled,
        });
    }

    if (repos.items.len == 0) {
        return error.norepospleasereaddcore; // technichally will not happen under normal circumstances as xpk auto creates core repo on first use, but if you rm the file its a helpful debugger
    }

    return repos.toOwnedSlice(allocator);
}

pub fn parse_a(allocator: std.mem.Allocator, text: []const u8) !types.Xbuild {
    var parser = automl.Parser.init(allocator);
    var doc = parser.parse(text) catch |err| {
        log.err("{f}\n", .{parser.diag});
        return err;
    };
    defer doc.deinit();

    var result: types.Xbuild = .{};

    // errors, union of both original errors automl doesn't know which sections xbuild requires
    if (doc.section("info") == null) return error.missinginfo;
    if (doc.section("pkg") == null) return error.missingpkg;
    if (doc.section("build") == null) return error.missingbuild;

    // [info]
    result.info.homepage = try get_str_dup(&doc, "info", "homepage", allocator) orelse "";
    result.info.upstream = try get_str_dup(&doc, "info", "upstream", allocator);
    result.info.name = try get_str_dup(&doc, "info", "name", allocator) orelse "";
    result.info.version = try get_str_dup(&doc, "info", "version", allocator) orelse "";
    result.info.desc = try get_str_dup(&doc, "info", "desc", allocator) orelse return error.missingdesc;
    result.info.license = try get_str_dup(&doc, "info", "license", allocator) orelse return error.missinglicense;
    result.info.deps = try get_strarr_dup_or_empty(&doc, "info", "deps", allocator);
    result.info.message = try get_str_dup(&doc, "info", "message", allocator) orelse "";

    // [pkg]
    result.pkg.src_url = try get_str_dup(&doc, "pkg", "src-url", allocator) orelse "";
    result.pkg.sha256sum = try get_str_dup(&doc, "pkg", "sha256", allocator) orelse "";

    if (try doc.get_str("pkg", "strip")) |strip| {
        if (!(std.mem.eql(u8, strip, "1") or
            std.mem.eql(u8, strip, "2") or
            std.mem.eql(u8, strip, "3")))
        {
            return error.badstripabove3;
        }
        result.pkg.strip = try allocator.dupe(u8, strip);
    }

    result.pkg.pre_hooks = try get_strarr_dup_or_empty(&doc, "pkg", "pre-hooks", allocator);

    // [build]
    result.build.build_sys = try get_str_dup(&doc, "build", "build-sys", allocator) orelse "";
    result.build.script = try get_str_dup(&doc, "build", "script", allocator);
    result.build.post_hooks = try get_strarr_dup_or_empty(&doc, "build", "post-hooks", allocator);
    result.build.args = try get_strarr_dup_or_empty(&doc, "build", "args", allocator);
    result.build.build_deps = try get_strarr_dup_or_empty(&doc, "build", "build-deps", allocator);

    if (result.pkg.src_url.len == 0) return error.missingsrcurl;
    if (result.pkg.sha256sum.len == 0) return error.missingsha256sum;

    return result;
}

pub fn parse_c(allocator: std.mem.Allocator, text: []const u8) !types.Config {
    var parser = automl.Parser.init(allocator);
    var doc = parser.parse(text) catch |err| {
        log.err("{f}\n", .{parser.diag});
        return err;
    };
    defer doc.deinit();

    var cfg: types.Config = .{};

    // [core]
    if (try doc.get_str("core", "verbosity")) |v| cfg.verbosity = try allocator.dupe(u8, v);
    if (try doc.get_bool("core", "color")) |v| cfg.color = v;
    if (try doc.get_bool("core", "confirm")) |v| cfg.confirm = v;

    // [download]
    if (try doc.get_int("download", "repo-jobs")) |v| cfg.repo_jobs = @intCast(v);
    if (try doc.get_int("download", "pkg-jobs")) |v| cfg.pkg_jobs = @intCast(v);
    if (try doc.get_int("download", "retries")) |v| cfg.retries = @intCast(v);
    if (try doc.get_int("download", "timeout")) |v| cfg.timeout = @intCast(v);
    if (try doc.get_bool("download", "prog")) |v| cfg.prog = v;

    // [build]
    if (try doc.get_str("build", "build-usr")) |v| cfg.build_usr = try allocator.dupe(u8, v);
    if (try doc.get_str("build", "build-path")) |v| cfg.build_path = try allocator.dupe(u8, v);
    if (try doc.get_bool("build", "keep-stage")) |v| cfg.keep_stage = v;
    if (try doc.get_int("build", "jobs")) |v| cfg.jobs = @intCast(v);

    // [store]
    if (try doc.get_int("store", "max-gens")) |v| cfg.max_gens = @intCast(v);
    if (try doc.get_bool("store", "autogc")) |v| cfg.autogc = v;

    // [repo]
    if (try doc.get_int("repo", "def-prio")) |v| cfg.def_prio = @intCast(v);
    if (try doc.get_bool("repo", "verify-sig")) |v| cfg.verify_sig = v;

    // [sandbox]
    if (try doc.get_bool("sandbox", "sandbox")) |v| cfg.sandbox = v;
    if (try doc.get_bool("sandbox", "sandbox-net")) |v| cfg.sandbox_net = v;

    // [misc]
    if (try doc.get_str("misc", "logfile")) |v| cfg.logfile = try allocator.dupe(u8, v);

    return cfg;
}