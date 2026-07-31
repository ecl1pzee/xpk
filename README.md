The XPK package manager
=======================
![Made with Zig](https://img.shields.io/badge/Made%20with-Zig-F7A41D?logo=zig&logoColor=white)
![Made with C](https://img.shields.io/badge/Made%20with-C-F7A14D?logo=c&logoColor=white)
![Status](https://img.shields.io/badge/status-development-blue)
![GitHub License](https://img.shields.io/github/license/fischblob-lol/xpk) 

Our discord: https://discord.gg/sDphynpzW

XPK is a source, and binary based package manager
that aims to be secure, powerful and user friendly, while also being highly debuggable!


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
