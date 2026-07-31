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

// xpk.conf
pub const Config = struct {

    // [core]
    verbosity: []const u8 = "info",  // quiet/err/warn/info/debug1/debug2/debug3/trace
    color: bool = true,              // ansi color codes 
    confirm: bool = true,            // whether install prompt actually prompts
    
    // [download] 
    repo_jobs: u32 = 4,               // max repos, defaults to 4 
    pkg_jobs: u32 = 1,                // max packages fetched concurrently, for later
    retries: u32 = 3,                // retry attempts on a failed download before giving up
    timeout: u32 = 30,               // seconds before a stalled download is considered dead
    prog: bool = true,              // show the [#####] progress bar or / spinner

    // [build] —
    build_usr: []const u8 = "xpk",           // unprivileged system account build/hook steps run as (see run.zig's su xpk -c)
    build_path: []const u8 = "/opt/xpk/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin", // path exported, i figured it would be nice
    keep_stage: bool = false,         // for debugging
    jobs: u32 = 0,                   // build jobs, gets appended as an arg in build

    // [store] 
    max_gens: u32 = 5,                // maximum generations allowed
    autogc: bool = false,            // auto prune gens each install

    // [repo] 
    def_prio: u8 = 0,                 // fallback priority, though this shouldn't happen
    verify_sig: bool = true,          // require valid sigs

    // [sandbox] (future)
    sandbox: bool = true,           // master toggle for sandboxed builds, will get its own wrapper
    sandbox_net: bool = false,        // whether sandboxed build steps get network access at all, usually not (arch gotta learn from us foreallll)

    // [misc]
    logfile: ?[]const u8 = null,     // optional shit, will add more optional shit
};