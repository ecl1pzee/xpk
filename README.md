The XPK package manager
=======================
<p allign="center>
<img src="https://img.shields.io/badge/opsex-black?style=for-the-badge&logo=shieldsdotio" alt="Badge">
<img src="https://img.shields.io/badge/zig-black?style=for-the-badge&logo=zig" alt="Badge">
<img src="https://img.shields.io/badge/clang-black?style=for-the-badge&logo=c" alt="Badge">
<img src="https://img.shields.io/badge/status-development-black?style=for-the-badge&labelColor=363636" alt="Badge">
<img src="https://img.shields.io/badge/license-bsd--2--clause-black?style=for-the-badge&labelColor=363636" alt="Badge">
<img src="https://img.shields.io/badge/opsex-black?style=for-the-badge&logo=shieldsdotio" alt="Badge">
</p>

XPK is a source, and binary based package manager
that aims to be secure, powerful and user friendly, while also being highly debuggable!

Philosophy and design
=========
**XPK** is a source and binary package manager designed to be secure, atomic, powerful, and highly debuggable without sacrificing ease of use.

This design is inspired by the philosophy behind OSTree, the operating system should be deployed as a complete, consistent state instead of being modified incrementally. However, XPK remains a traditional package manager, supporting both source based and binary packages while providing atomic deployments and reliable rollbacks.

Everything is consistent. If data is garbage and unused, the gc finds it and removes it. If your package breaks? Rollback a package. Big system update that breaks god know what? Rolback entire system.

We try to not deviate from this philosophy, but later there may be changes to the philosophy itself, and it may become its own entire, unqiue way of managing packages.

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
    Fingerprint: 79E7 72B2 0F99 B152 1BBB 49C6 5BF7 4E3E D886 8135 

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
