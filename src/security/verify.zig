const std = @import("std");
const Ed25519 = std.crypto.sign.Ed25519;
const idxtypes = @import("../index/types/types.zig");
const keyringtypes = @import("../parsers/types/types.zig");
//verity error
pub const Verifyerror = error{ notenoughsigs, badfingerprint };

// anyways simple file it just verifies stuff, needs a signed idx and parsed keyring tho

// shit sigs from unrecognized fingerprints just gets ignored, they don't help or hurt, requires a keyring struct from keyring.autm
pub fn verify_s(signed: idxtypes.Signedidx, keyring: keyringtypes.Keyring) !void {
    var validcount: u32 = 0;

    for (signed.sigs) |sig| {
        const fphex = std.fmt.bytesToHex(sig.fingerprint, .lower);
        // does exactly what it says, finds a signer
        const key = find_signer(keyring.maintainers, &fphex) orelse (find_signer(keyring.helpers, &fphex) orelse continue);

        if (!key.active or key.revoked) continue; // known but non trusted so skip

        const pubkey = Ed25519.PublicKey.fromBytes(sig.fingerprint) catch continue; // malformed pubkey bytes, also skip
        const signature = Ed25519.Signature.fromBytes(sig.signature);

        signature.verify(signed.body, pubkey) catch continue; // bad sig, skip

        validcount += 1;
    }

    if (validcount < keyring.requiredsigs) return Verifyerror.notenoughsigs;
}

fn find_signer(map: std.StringHashMap(keyringtypes.Key), fphex: []const u8) ?keyringtypes.Key {
    var it = map.iterator();
    while (it.next()) |entry| {
        if (std.mem.eql(u8, entry.value_ptr.fingerprint, fphex)) return entry.value_ptr.*;
    }
    return null;
}