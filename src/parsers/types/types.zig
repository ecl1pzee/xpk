const std = @import("std");

// changes for automl, after this comit im gonna work on automl
pub const Info = struct {
    homepage: []const u8 = "",
    upstream: ?[]const u8 = "",
    name: []const u8 = "",
    version: []const u8 = "",
    desc: ?[]const u8 = null,
    license: ?[]const u8 = null,
    deps: ?[]const []const u8 = null, // was ?[][]const u8
};

pub const Pkg = struct {
    src_url: []const u8 = "",
    sha256sum: []const u8 = "",
    strip: ?[]const u8 = null,
    pre_hooks: ?[]const []const u8 = null, // was ?[][]const u8
};

pub const Build = struct {
    build_sys: []const u8 = "",
    build_deps: ?[]const []const u8 = null, // was ?[][]const u8
    args: ?[]const []const u8 = null,       // was ?[][]const u8
    script: ?[]const u8 = null,
    post_hooks: ?[]const []const u8 = null, // was ?[][]const u8
};

// spec, left for parser_tests.zig 
pub const Spec = struct {
    pkg: Pkg = .{},
    build: Build = .{},
};

// the file containing everything
pub const Xbuild = struct {
    info: Info = .{},
    pkg: Pkg = .{},
    build: Build = .{},
};

// will eventually get more values, more optionals, more complex things, architechture, etc, hence why kept in a seperate file this time
// uppercase naming convention for structs

pub const Key = struct {
    fingerprint: []const u8 = "",
    added: []const u8 = "",
    active: bool = false, // defaults if not listed
    revoked: bool = false, // defaults
};

pub const Keyring = struct {
    maintainers: std.StringHashMap(Key), // first use of stringhash maps in my life, anyways here these are useful because maintainers and helpers do use the same string, and a hash map is useful here
    helpers: std.StringHashMap(Key),

    head: []const u8 = "", // default to nothing, but ill make these required some time for the sake of safety
    hashlastedit: []const u8 = "",

    requiredsigs: u32 = 1,
    allowhelpers: bool = true,
};
 
 //repos
pub const Repo = struct {
    name: []const u8 = "",
    url: []const u8 = "",
    priority: u8 = 0,
    enabled: bool = true,
};