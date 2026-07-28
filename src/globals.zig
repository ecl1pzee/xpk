//! globals file
//! it has globals
//! globals that will change eventually
//! thats it
//! especially they will change when porting to linux
//! real

pub const base = "/opt/xpk";
pub const db = base ++ "/db";
pub const tmp = "/tmp/xpk"; //isolation man

pub const local = base ++ "/repos";
pub const reposconf = local ++ "/repos.conf";   // fixed
pub const firstrun = base ++ "/.xpk";           // fixed
pub const conf = base ++ "/xpk.conf"; 
// wow 
pub const buildusr = "xpk";

pub const stage = tmp ++ "/stage"; // destdir, package installs go in here
pub const dbfile = db ++ "/db"; // like the index files, this is in a binary format simmilar to that of 