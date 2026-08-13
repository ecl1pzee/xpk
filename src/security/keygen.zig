//! this is a more 'developer exclusive' tool
//! however xpk is also made because you can easily host your own repos!
//! soon ill add even git support through private ones, if you feel like gatekeeping
//! so i keep this in the same binary for easy use, no point to start another repo.
//! altough, i might actually make this into a xpk tool like xpk-sign, but that will happen later
//! and may not happen at all
//! needs a rework to where the keys actually, go.
//! fuck i've looked at the std and cant find any env mapper
//! shit
const std = @import("std");
const Ed25519 = std.crypto.sign.Ed25519;
const globals = @import("../globals.zig");
const log = @import("../utils/log.zig");
const utils = @import("../utils/utils.zig");
const print = std.debug.print;

pub const Keygenerror = error{ keyalreadyexists, writefailed };

// where keypairs exist, these are not in globals because keygen ONLY appears here
pub fn keydir() []const u8 {
    return globals.base ++ "/keys";
}

fn privpath() []const u8 {
    return globals.base ++ "/keys/priv.key";
}

fn pubpath() []const u8 {
    return globals.base ++ "/keys/pub.key";
}

fn fingerprintpath() []const u8 {
    return globals.base ++ "/keys/fingerprint";
}



fn createdir(io: std.Io, path: []const u8) !void {
    return utils.fs.createdir(io, path);
}


// generates a new ed25519 keypair for signing index, not veriyifying shit because the user verifies via keyring
pub fn generate(io: std.Io) !void {
    log.trace("starting key generation\n", .{});

    try createdir(io, keydir());

    log.debug1("checking for existing keypair\n", .{});

    if (std.Io.Dir.openFileAbsolute(io, privpath(), .{ .mode = .read_only })) |f| {
        f.close(io);

        log.warn("private key already exists, refusing overwrite\n", .{});
        return Keygenerror.keyalreadyexists;
    } else |err| if (err != error.FileNotFound) {
        log.err("failed checking private key: {s}\n", .{@errorName(err)});
        return err;
    }

    log.debug1("generating Ed25519 keypair\n", .{});

    const kp = Ed25519.KeyPair.generate(io);

    log.debug2("writing private key\n", .{});

    {
        const file = std.Io.Dir.createFileAbsolute(io, privpath(), .{ .truncate = true }) catch |err| {
            log.err("failed creating private key: {s}\n", .{@errorName(err)});
            return err;
        };
        defer file.close(io);

        try file.setPermissions(io, std.Io.File.Permissions.fromMode(0o600));

        var writerbuf: [128]u8 = undefined;
        var fwriter = file.writer(io, &writerbuf);

        fwriter.interface.writeAll(&kp.secret_key.bytes) catch |err| {
            log.err("failed writing private key: {s}\n", .{@errorName(err)});
            return err;
        };

        try fwriter.interface.flush();
    }

    log.debug2("writing public key\n", .{});

    {
        const file = try std.Io.Dir.createFileAbsolute(io, pubpath(), .{ .truncate = true });
        defer file.close(io);

        try file.setPermissions(io, std.Io.File.Permissions.fromMode(0o644));

        var writerbuf: [64]u8 = undefined;
        var fwriter = file.writer(io, &writerbuf);

        try fwriter.interface.writeAll(&kp.public_key.toBytes());
        try fwriter.interface.flush();
    }

    log.debug2("writing fingerprint\n", .{});

    {
        const file = try std.Io.Dir.createFileAbsolute(io, fingerprintpath(), .{ .truncate = true });
        defer file.close(io);

        try file.setPermissions(io, std.Io.File.Permissions.fromMode(0o644));

        const hex = std.fmt.bytesToHex(kp.public_key.toBytes(), .lower);

        var writerbuf: [80]u8 = undefined;
        var fwriter = file.writer(io, &writerbuf);

        try fwriter.interface.writeAll(&hex);
        try fwriter.interface.writeAll("\n");
        try fwriter.interface.flush();
    }

    log.success("generated keypair\n", .{});

    log.info("fingerprint: {x}\nprivate key stored at: {s}\n",.{kp.public_key.toBytes(), privpath()});
}

// loads the keypair for signing, if the key is exposed it errors and urges you to well, fix the thing duh, key_load
pub fn key_l(io: std.Io) !Ed25519.KeyPair {
    log.trace("loading signing key\n", .{});

    const file = std.Io.Dir.openFileAbsolute(io, privpath(), .{ .mode = .read_only }) catch |err| {
        log.err("failed opening private key: {s}\n", .{@errorName(err)});
        return err;
    };
    defer file.close(io);

    const st = try file.stat(io);
    const mode = st.permissions.toMode() & 0o777;

    log.debug2("private key permissions are {o}\n", .{mode});

    if (mode != 0o600) {
        log.err("private key has insecure permissions ({o}), refusing load\n",.{mode});
        return error.insecurekeypermissions;
    }

    var buf: [64]u8 = undefined;
    var readbuf: [64]u8 = undefined;
    var freader = file.reader(io, &readbuf);
    freader.interface.readSliceAll(&buf) catch |err| {
        log.err("failed reading private key: {s}\n", .{@errorName(err)});
        return err;
    };

    log.debug1("private key loaded, rebuilding keypair\n", .{});

    const secret = Ed25519.SecretKey.fromBytes(buf) catch {
        log.err("private key contents are corrupted\n", .{});
        return error.corruptkey;
    };

    log.success("loaded signing key\n", .{});
    return try Ed25519.KeyPair.fromSecretKey(secret);
}

// signs data with the given keypair, returns the raw 64-byte signature, thats it
pub fn sign(kp: Ed25519.KeyPair, data: []const u8) ![64]u8 {
    log.trace("signing {d} bytes\n", .{data.len});
    const sig = try kp.sign(data, null);

    log.debug2("generated signature\n", .{});
    return sig.toBytes();
}