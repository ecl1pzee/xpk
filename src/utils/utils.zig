//! header file
//! like the good old neo days
const xpkcli = @import("cli.zig");
const parsers = @import("../parsers/parsers.zig");
const downloader = @import("../downloader/downloader.zig");
const hash = @import("../security/hasher.zig");
const index = @import("../index/index.zig");
const fetcher = @import("../fetch/rfetch.zig");
const pull = @import("../fetch/rpull.zig");
const build = @import("../parsers/types/types.zig");
const dispatcher = @import("../build/dispatch.zig");
const extractor = @import("../extract/extract.zig");
const verity = @import("../security/verify.zig"); // ask me anything
const keygen = @import("../security/keygen.zig");
const mlist = @import("../misc/list.zig");
const fsutil = @import("fsutil.zig");
const garbage = @import("../gc/gc.zig");
const stratumforeal = @import("../stratum/stratum.zig");
const rollbackforeal = @import("../rollback/rollback.zig");

pub const cli = struct {
    pub const helpmenu = xpkcli.helpmenu;
    pub const version = xpkcli.version;
    pub const global_confirm = xpkcli.global_confirmer;
    pub const package_confirm = xpkcli.package_confirm;
    pub const root = xpkcli.root;
};

pub const parser = struct {
    pub const parse_r = parsers.parse_r;
    pub const parse_a = parsers.parse_a;
    pub const parse_k = parsers.parse_k; 
    
    pub const Repo = build.Repo;
    pub const Build = build.Build;
    pub const Pkg = build.Pkg;
};

pub const indexer = struct {
    pub const index_repo = index.index_repo;
};

pub const installer = struct {
    pub const download = downloader.download;
    pub const remote_fetch = fetcher.remote_fetch;
};

pub const builder = struct {
    pub const run_build = dispatcher.run_build;
};

pub const extract = struct {
    pub const extract_tar = extractor.extract_tar;
};

pub const sync = struct {
    pub const pull_repo = pull.pull_repo;
    pub const init_repo = pull.init_repos;
    pub const download_repos = downloader.download_repo;
};

pub const security = struct {
    pub const get_hash = hash.get_hash;
    pub const get_hashb = hash.get_hashb;
    pub const verify_s = verity.verify_s;
    pub const generate = keygen.generate;
    pub const sign = keygen.sign;
    pub const key_l = keygen.key_l;
    
};

pub const misc = struct {
    pub const list = mlist.list;
    pub const search = mlist.search;
    pub const info = mlist.info;
};

pub const fs = struct {
    pub const createdir = fsutil.createdir;
    pub const rename = fsutil.rename;
};

pub const gc = struct {
    pub const run = garbage.run;
};

pub const stratum = struct {
    pub const seal = stratumforeal.seal_stratum;
    pub const revert = stratumforeal.revert_stratum;
    pub const history = stratumforeal.history;
    pub const Action = stratumforeal.Action;
};

pub const rollback = struct {
    pub const pkg = rollbackforeal.rollback_pkg;
    pub const system = rollbackforeal.rollback_sys;
};