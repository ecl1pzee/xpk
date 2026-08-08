The XPK package manager
=======================
![Made with Zig](https://img.shields.io/badge/Made%20with-Zig-F7A41D?logo=zig&logoColor=white)
![Made with C](https://img.shields.io/badge/Made%20with-C-F7A14D?logo=c&logoColor=white)
![Status](https://img.shields.io/badge/status-development-blue)
![GitHub License](https://img.shields.io/github/license/fischblob-lol/xpk) 

well fuck you dude

XPK is a source, and binary based package manager
that aims to be secure, powerful and user friendly, while also being highly debuggable!

Philosophy and design
=========
**XPK** is a source and binary package manager designed to be secure, atomic, powerful, and highly debuggable without sacrificing ease of use.

This design is inspired by the philosophy behind OSTree, the operating system should be deployed as a complete, consistent state instead of being modified incrementally. However, XPK remains a traditional package manager, supporting both source based and binary packages while providing atomic deployments and reliable rollbacks.

Everything is consistent. If data is garbage and unused, the gc finds it and removes it. If your package breaks? Rollback a package. Big system update that breaks god know what? Rolback entire system.

We try to not deviate from this philosophy, but later there may be changes to the philosophy itself, and it may become its own entire, unqiue way of managing packages.

Security Model (not exactly in order of how it happens)
==============

XPK is designed with one primary goal: making software supply chain attacks as difficult as practically possible. Rather than relying on a single security mechanism, XPK employs multiple independent verification layers. An attacker must bypass every layer for malicious software to reach a user's system.

Repository Authentication
========================

Every repository is cryptographically signed. Before any package metadata is trusted, XPK verifies the repository's signature against the user's trusted keyring.

Without access to a trusted repository signing key, an attacker cannot distribute modified package metadata or manifests through an official repository.

Build Manifest Verification
===========================

Every repository index contains cryptographic hashes for every indexed xbuild.

Whenever a repository is synchronized, XPK verifies that each downloaded xbuild exactly matches the hash recorded in the index. Even when a repository is locked to a specific commit, these hashes are verified again as an additional integrity check.

If any xbuild has been modified, corrupted, or tampered with after the index was generated (which shouldnt happen), verification immediately fails and the installation is aborted.

Source Archive Verification
===========================

After downloading a source archive, XPK performs another SHA-256 verification against the hash declared inside the xbuild.

Only archives that exactly match the expected digest are accepted. Any mismatch immediately aborts the installation.

Sandboxed Builds
================

Packages are built inside a fully isolated sandbox.

The build environment has no unintended access to the host system outside of the temporary directory, preventing build scripts from modifying user files or interacting with the operating system outside the sandbox. In addition, builds execute under a dedicated unprivileged user, providing another layer of containment should a malicious build script attempt to escape, and later on will report these incidents.

Binary Behavior Verification *(im doing this next)* 
=========================================

After a package is built, XPK will analyze the resulting binaries using zre (currently under development)

Instead of merely comparing hashes, the verifier will inspect binary behavior and compare it against previous trusted builds.

Package manifests may define explicit security policies describing what a binary is allowed to do. For example:

* Network access
* Socket creation
* ptrace
* Loading shared libraries
* Executing subprocesses
* trying to debug other process memory
* Other privileged or potentially dangerous operations

Think of it as, a very small antivirus and threat prevention system

If a newly built binary performs operations outside its declared policy or significantly differs (and by significantly, i mean a tool like ls from coreutils suddenly using internet) from previously trusted versions, XPK will refuse installation.

The user will receive a detailed security report explaining why the package was rejected, along with information for contacting the repository maintainers to report a potentially compromised package, or a package that simply violates policies.

This layer is intended to detect malicious behavior even when cryptographic signatures and hashes remain valid for example, if an attacker has compromised an official repository or maintainer account, and had implemented a malicious build.

Reproducible Builds 
==============================

XPK aims to eventually provide a fully deterministic build environment capable of reproducing packages bit for bit, which is simply to expensive and complex for me right now as i have limited knowledge on why reproduced builds actually work.

Once a package has successfully passed binary verification, XPK will rebuild it independently and compare the produced binaries against the expected output, which is later probably also going to be stored in the index files.

If the reproduced build differs by even a single bit, installation will be rejected, and warned. 

It is important to note that reproducibility alone does not prove software is safe. If a repository intentionally distributes malicious source code, a reproducible build would faithfully reproduce that malware, and this would make this layer pretty much obselete.

Build Output verification
=========================

XPK will aim to have a build output verification, where if packages tries to overwrite another package, it can easily be stopped by checking the trees file, plus this is difficult in practice for the attacker too because of how our hashing system works, and stratums + stratus.

If that happens, package will be rejected for install for violating policy.

Builder Consensus 
=================

If package exists in multiple repos, and hash of everything for the package is the same for multiple repos (especially approved) except yours, then it warns, will probably be like a simple message you can Y/n.

Basically, using quantity to approve of quality.

Proof of build
===============

When a package is built, XPK will record a signed reciept containing:

- compiler version
- linker version
- libc version
- kernel headers
- environment variables
- build flags
- repository commit
- source hashes
- binary hash

in the future, this reciept will be stored inside/alongside a tar file containing binary package.

Defense in Depth
================

Nothing is perfect. Nothing is perfect mathematically, a professional exploiter can penetrate/attack almost any supply chain given enough time, so XPK combines all said layers to minimize possible colateral damage, or make it engineerically impossible. (not possible for standard people, even with mid end tools)

Each layer protects against a different class of attack, with almost all of these in play, chances are greatly reduced.

Compromising the first layer already requires control of a trusted repository or its signing keys. Bypassing the behavioral verification layer becomes substantially more difficult, as malicious changes must also evade binary analysis and policy enforcement, and would need SE (social engineering) to actually get the ability to verify and commit, and trying to bypass sandboxing and such would be almost impossible to anyone without access to the owner of the repo, to fully modify every part, and even then i will add a first response system to these cases.

The objective of XPK is to try and minimize the security risk many package managers upbring, especially with custom repositories.


Compatibility 
==============
It supports:
1. musl  systems
2. glibc systems
3. XNU/Darwin systems (x86_64)
4. XNU/Darwin systems (arm64)
5. Anything unix-like that is not super-niche

It does not(and probably never will) support:
1. Windows (32bit)
2. Windows (64bit)
3. Windows (arm64)
4. Literally anything that isn't unix-like

License
=======
XPK uses the 2-Clause BSD License. More info about it at: https://opensource.org/license/bsd-2-clause

# Verifying releases

> [!IMPORTANT]
> XPK releases are signed with these keys, for both the core repository
> and the package manager, from now on.

aurelius (xpk maintainer)
--------------------------
    Fingerprint: 7194 59C4 0E06 BCD8 7785 528F 48DC 1015 5AE4 87B5

    Fetch via:
    gpg --keyserver keys.openpgp.org --recv-keys 79E772B20F99B1521BBB49C65BF74E3ED8868135

    Or view directly:
    https://keys.openpgp.org/search?q=79E772B20F99B1521BBB49C65BF74E3ED8868135

eclipse_dev (xpk maintainer)
--------------------------------
    Fingerprint: D9F7 0FAA AD6F A15D 6BC3 C755 9B4F B4E0 8086 1302

    Fetch via:
    gpg --keyserver keys.openpgp.org --recv-keys D9F70FAAAD6FA15D6BC3C7559B4FB4E080861302

    Or view directly:
    https://keys.openpgp.org/search?q=D9F70FAAAD6FA15D6BC3C7559B4FB4E080861302

A release signed by either key should be considered valid. If you
notice a release signed by a key not listed here, treat it as
untrusted and please open an issue, although this shan't happen.

Documentation
=============
At the moment, XPK is **temporarily** documented on NeoCities.org.

We will plan on switching to something else, for example codeberg pages.

For the time being, documentation is hosted at: https://xnu-package-kit.neocities.org and is maintained by firewald and firewald only.


Check out our other projects!
====
###  <p align="middle"><em>maintained by <a href="https://github.com/aureliusxyz">aurelius</a></em></p>
### [automl](https://github.com/aureliusxyz/automl)
*A small, portable TOML-ish parser library with zero deps, dotted sections, nested arrays, pretty diagnostics.*
