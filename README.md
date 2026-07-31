The XPK package manager
=======================
![Made with Zig](https://img.shields.io/badge/Made%20with-Zig-F7A41D?logo=zig&logoColor=white)
![Made with C](https://img.shields.io/badge/Made%20with-C-F7A14D?logo=c&logoColor=white)
![Status](https://img.shields.io/badge/status-development-blue)
![GitHub License](https://img.shields.io/github/license/fischblob-lol/xpk) 

Our discord: https://discord.gg/sDphynpzW

XPK is a source, and binary based package manager
that aims to be secure, powerful and user friendly, while also being highly debuggable!

Philosophy
=========
**XPK** is a source and binary package manager designed to be secure, atomic, powerful, and highly debuggable without sacrificing ease of use.

This design is inspired by the philosophy behind OSTree: the operating system should be deployed as a complete, consistent state instead of being modified incrementally. However, XPK remains a traditional package manager, supporting both source based and binary packages while providing atomic deployments and reliable rollbacks.

Unlike systems that depend on fully reproducible builds, XPK acknowledges that many real world packages cannot currently be reproduced bit by bit, Instead of relying solely on reproducible package outputs, XPK has good security, and focuses on a more customisable and non bloatful approach.

To minimize storage usage, XPK stores efficient filesystem differences between generations whenever possible while preserving the ability to reconstruct complete states. This allows multiple generations to coexist without duplicating unchanged data, enabling fast upgrades, rollbacks, and historical inspection.

Every download produces a new generation of the affected package or environment. Previous generations remain available until explicitly removed with the (upcoming gc), allowing users to instantly revert failed upgrades, compare changes between versions, or inspect exactly what was modified during any transaction.

Security is a the biggest design goal. Packages are isolated during builds, repository metadata and package contents are cryptographically verified, and installations are never allowed to leave the system in a partially updated state. Every operation is deterministic from the package manager's perspective either the entire transaction succeeds and becomes active, or nothing changes.

XPK also separates package construction from deployment. Source packages are built in isolated environments to produce a complete filesystem tree, while binary packages provide pre built trees ready for deployment. 

Although, in v2 of the package manager, reproducible builds will infact be added simply for the sake of security, possibly as a toggled option or default.



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
    gpg --keyserver keys.openpgp.org --recv-keys 719459C40E06BCD87785528F48DC10155AE487B5

    Or view directly:
    https://keys.openpgp.org/search?q=719459C40E06BCD87785528F48DC10155AE487B5

eclipse_dev (xpk maintainer)
--------------------------------
    Fingerprint: D9F7 0FAA AD6F A15D 6BC3 C755 9B4F B4E0 8086 1302

    Fetch via:
    gpg --keyserver keys.openpgp.org --recv-keys D9F70FAAAD6FA15D6BC3C7559B4FB4E080861302

    Or view directly:
    https://keys.openpgp.org/search?q=D9F70FAAAD6FA15D6BC3C7559B4FB4E080861302

> [!WARNING]
> Due to ecl1pse (previously firewald/fischblob-lol) switching operating systems from
> endeavourOS to FreeBSD. they want to also get new pgp keys
> capiche?

A release signed by either key should be considered valid. If you
notice a release signed by a key not listed here, treat it as
untrusted and please open an issue, although this shan't happen.

Documentation
=============
At the moment, XPK is **temporarily** documented on NeoCities.org.

We will plan on switching to something else, for example codeberg pages.

For the time being, documentation is hosted at: https://xnu-package-kit.neocities.org and is maintained by firewald and firewald only.

How can I say thanks?
=====================
Spread the word!

Star history
============
<a href="https://www.star-history.com/?repos=fischblob-lol%2Fxpk&type=date&legend=bottom-right">
 <picture>
   <source media="(prefers-color-scheme: dark)" srcset="https://api.star-history.com/chart?repos=fischblob-lol/xpk&type=date&theme=dark&legend=bottom-right&sealed_token=JByaEYclA6Eohd-SAgoM5MR2IE8P5tkyuFdSG_6kUQuL_ZzTYGBztUvJjrvYaNNhbAblF-h1Ql3Vsu6aiehxiz3crISQrI9G1DLOelPyiCVeJgCfkUOHVyWcw0oIeAogioWJT2j9jI4u_ZChZSSgX3f3IcTQaBjFPCHGZNg0uyszYp3GNaAK6oZVA3_0" />
   <source media="(prefers-color-scheme: light)" srcset="https://api.star-history.com/chart?repos=fischblob-lol/xpk&type=date&legend=bottom-right&sealed_token=JByaEYclA6Eohd-SAgoM5MR2IE8P5tkyuFdSG_6kUQuL_ZzTYGBztUvJjrvYaNNhbAblF-h1Ql3Vsu6aiehxiz3crISQrI9G1DLOelPyiCVeJgCfkUOHVyWcw0oIeAogioWJT2j9jI4u_ZChZSSgX3f3IcTQaBjFPCHGZNg0uyszYp3GNaAK6oZVA3_0" />
   <img alt="Star History Chart" src="https://api.star-history.com/chart?repos=fischblob-lol/xpk&type=date&legend=bottom-right&sealed_token=JByaEYclA6Eohd-SAgoM5MR2IE8P5tkyuFdSG_6kUQuL_ZzTYGBztUvJjrvYaNNhbAblF-h1Ql3Vsu6aiehxiz3crISQrI9G1DLOelPyiCVeJgCfkUOHVyWcw0oIeAogioWJT2j9jI4u_ZChZSSgX3f3IcTQaBjFPCHGZNg0uyszYp3GNaAK6oZVA3_0" />
 </picture>
</a>


Check out our other projects!
====
###  <p align="middle"><em>maintained by <a href="https://github.com/aureliusxyz">aurelius</a></em></p>
### [automl](https://github.com/aureliusxyz/automl)
*A small, portable TOML-ish parser library with zero deps, dotted sections, nested arrays, pretty diagnostics.*
