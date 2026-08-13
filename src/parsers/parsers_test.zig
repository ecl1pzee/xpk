const std = @import("std");
const parsers = @import("parsers.zig");
const types = @import("types/types.zig");

const parse_k = parsers.parse_k;

// why do i even have these atp i have 49 automl tests- 

test "parse_k parses a full keyring" {
    const allocator = std.testing.allocator;

    const text =
        \\
        \\[policy]
        \\required-signatures = 2
        \\allow-helpers = true
        \\
        \\[maintainers.rocky]
        \\fingerprint = "AAAA BBBB CCCC DDDD"
        \\added = "2026-01-01 00:00"
        \\active = true
        \\revoked = false
        \\
        \\[helpers.someone]
        \\fingerprint = "1111 2222 3333 4444"
        \\added = "2026-05-15 09:00"
        \\active = true
        \\revoked = false
    ;

    var result = try parse_k(allocator, text);
    defer {
        result.maintainers.deinit();
        result.helpers.deinit();
    }

  
    // [policy]
    try std.testing.expectEqual(@as(u32, 2), result.requiredsigs);
    try std.testing.expectEqual(true, result.allowhelpers);

    // [maintainers.rocky]
    const rocky = result.maintainers.get("rocky") orelse return error.TestExpectedEqual;
    try std.testing.expectEqualStrings("AAAA BBBB CCCC DDDD", rocky.fingerprint);
    try std.testing.expectEqualStrings("2026-01-01 00:00", rocky.added);
    try std.testing.expectEqual(true, rocky.active);
    try std.testing.expectEqual(false, rocky.revoked);

    // [helpers.someone]
    const someone = result.helpers.get("someone") orelse return error.TestExpectedEqual;
    try std.testing.expectEqualStrings("1111 2222 3333 4444", someone.fingerprint);
    try std.testing.expectEqual(true, someone.active);
    try std.testing.expectEqual(false, someone.revoked);
}



const parse_r = parsers.parse_r;

test "parse_r parses multiple repos with host-specific url rewriting" {
    const allocator = std.testing.allocator;

    const text =
        \\[core]
        \\url = "https://codeberg.org/sundowner/xpk-c"
        \\priority = 1
        \\enabled = true
        \\
        \\[mirror]
        \\url = "https://github.com/sundowner/xpk-mirror"
        \\priority = 2
        \\enabled = false
        \\
        \\[custom]
        \\url = "https://example.com/repo"
    ;

    const repos = try parse_r(allocator, text);
    defer {
        for (repos) |repo| {
            allocator.free(repo.url);
        }
        allocator.free(repos);
    }

    try std.testing.expectEqual(@as(usize, 3), repos.len);

    // find each by name since section iteration order isn't guaranteed
    var core: ?types.Repo = null;
    var mirror: ?types.Repo = null;
    var custom: ?types.Repo = null;

    for (repos) |repo| {
        if (std.mem.eql(u8, repo.name, "core")) core = repo;
        if (std.mem.eql(u8, repo.name, "mirror")) mirror = repo;
        if (std.mem.eql(u8, repo.name, "custom")) custom = repo;
    }

    const c = core orelse return error.TestExpectedEqual;
    try std.testing.expectEqualStrings("https://codeberg.org/sundowner/xpk-c/raw", c.url);
    try std.testing.expectEqual(@as(u8, 1), c.priority);
    try std.testing.expectEqual(true, c.enabled);

    const m = mirror orelse return error.TestExpectedEqual;
    try std.testing.expectEqualStrings("https://github.com/sundowner/xpk-mirror/raw/main", m.url);
    try std.testing.expectEqual(@as(u8, 2), m.priority);
    try std.testing.expectEqual(false, m.enabled);

    const cu = custom orelse return error.TestExpectedEqual;
    try std.testing.expectEqualStrings("https://example.com/repo", cu.url); // unknown host, untouched
    try std.testing.expectEqual(@as(u8, 0), cu.priority); // default when absent
    try std.testing.expectEqual(true, cu.enabled); // default when absent
}

test "parse_r errors when no repos are defined" {
    const allocator = std.testing.allocator;

    const text = "";

    try std.testing.expectError(error.norepospleasereaddcore, parse_r(allocator, text));
}

test "parse_r errors on missing url" {
    const allocator = std.testing.allocator;

    const text =
        \\[core]
        \\priority = 1
        \\enabled = true
    ;

    try std.testing.expectError(error.missingurl, parse_r(allocator, text));
}

test "parse_r errors on invalid enabled value" {
    const allocator = std.testing.allocator;

    const text =
        \\[core]
        \\url = "https://example.com/repo"
        \\enabled = "notabool"
    ;

    try std.testing.expectError(error.invalidbool, parse_r(allocator, text));
}


const parse_a = parsers.parse_a;

test "parse_a parses a full xbuild with inline and multiline arrays" {
    const allocator = std.testing.allocator;

    const text =
        \\[info]
        \\homepage = "https://neovim.io"
        \\upstream = "https://github.com/neovim/neovim"
        \\name = "neovim"
        \\version = "0.12.4"
        \\desc = "Neovim is a project that seeks to aggressively refactor Vim"
        \\license = "Apache-2.0"
        \\deps = ["libuv", "luajit", "treesitter"]
        \\
        \\[pkg]
        \\src-url = "https://github.com/neovim/neovim/archive/v0.12.4.tar.gz"
        \\sha256 = "deadbeef"
        \\strip = "1"
        \\pre-hooks = [
        \\  "echo starting",
        \\  "mkdir -p build",
        \\]
        \\
        \\[build]
        \\build-sys = "cmake"
        \\script = "cmake --build ."
        \\args = ["-DCMAKE_BUILD_TYPE=Release"]
        \\build-deps = ["cmake", "ninja"]
        \\post-hooks = ["echo done"]
    ;

    const result = try parse_a(allocator, text);
    defer {
        if (result.info.deps) |d| allocator.free(d);
        if (result.pkg.pre_hooks) |h| allocator.free(h);
        if (result.build.args) |a| allocator.free(a);
        if (result.build.build_deps) |d| allocator.free(d);
        if (result.build.post_hooks) |h| allocator.free(h);
    }

    // [info]
    try std.testing.expectEqualStrings("https://neovim.io", result.info.homepage);
    try std.testing.expectEqualStrings("neovim", result.info.name);
    try std.testing.expectEqualStrings("0.12.4", result.info.version);
    try std.testing.expectEqualStrings("Apache-2.0", result.info.license.?);

    const deps = result.info.deps orelse return error.TestExpectedEqual;
    try std.testing.expectEqual(@as(usize, 3), deps.len);
    try std.testing.expectEqualStrings("libuv", deps[0]);
    try std.testing.expectEqualStrings("luajit", deps[1]);
    try std.testing.expectEqualStrings("treesitter", deps[2]);

    // [pkg]
    try std.testing.expectEqualStrings("deadbeef", result.pkg.sha256sum);
    try std.testing.expectEqualStrings("1", result.pkg.strip.?);

    const prehooks = result.pkg.pre_hooks orelse return error.TestExpectedEqual;
    try std.testing.expectEqual(@as(usize, 2), prehooks.len);
    try std.testing.expectEqualStrings("echo starting", prehooks[0]);
    try std.testing.expectEqualStrings("mkdir -p build", prehooks[1]);

    // [build]
    try std.testing.expectEqualStrings("cmake", result.build.build_sys);
    try std.testing.expectEqualStrings("cmake --build .", result.build.script.?);

    const args = result.build.args orelse return error.TestExpectedEqual;
    try std.testing.expectEqual(@as(usize, 1), args.len);
    try std.testing.expectEqualStrings("-DCMAKE_BUILD_TYPE=Release", args[0]);
}

test "parse_a errors on missing sections" {
    const allocator = std.testing.allocator;

    const text =
        \\[info]
        \\name = "cmatrix"
    ;

    try std.testing.expectError(error.missingpkg, parse_a(allocator, text));
}

test "parse_a errors on missing src-url" {
    const allocator = std.testing.allocator;

    const text =
        \\[info]
        \\name = "cmatrix"
        \\version = "2.0"
        \\
        \\[pkg]
        \\sha256 = "dd"
        \\
        \\[build]
        \\build-sys = "make"
    ;

    try std.testing.expectError(error.missingsrcurl, parse_a(allocator, text));
}

test "parse_a errors on invalid strip value" {
    const allocator = std.testing.allocator;

    const text =
        \\[info]
        \\name = "cmatrix"
        \\version = "2.0"
        \\
        \\[pkg]
        \\src-url = "https://example.com/cmatrix.tar.gz"
        \\sha256 = "dd"
        \\strip = "9"
        \\
        \\[build]
        \\build-sys = "make"
    ;

    try std.testing.expectError(error.badstripabove3, parse_a(allocator, text));
}