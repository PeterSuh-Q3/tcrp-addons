# Third-party notices for wifi-tools

This addon distributes third-party x86-64 Linux executables and shared
libraries. The same archive may be used by Tiny Core Linux-based loader
environments, Alpine-based loader/build environments, and the Synology DSM
junior ramdisk. The operating environment does not change the components'
licenses. Third-party components remain under their respective licenses; the
repository's own license does not replace those terms.

The following versions and license expressions are taken from Alpine 3.20
package metadata for the included files. License and copyright texts from the
respective upstream releases are in `licenses/` and in the archive.

| Alpine package | Version | License expression | Alpine build recipe revision |
| --- | --- | --- | --- |
| wpa_supplicant | 2.10-r11 | BSD-3-Clause | `04dce289411f1f794e0d7e9a43d4b7a908d2bf5b` |
| musl | 1.2.5-r3 | MIT | `b3006413508380c8a4e224006ef44c8394ca8c50` |
| libnl3 | 3.9.0-r1 | LGPL-2.1-or-later | `7073e8a28972fc9da78a7b9147b473e0299997ee` |
| pcsc-lite-libs | 2.2.3-r0 | BSD-3-Clause AND BSD-2-Clause AND ISC | `e17d150a99904da928b6fda8d95a1e2b5d40c934` |
| dbus-libs | 1.14.10-r1 | AFL-2.1 OR GPL-2.0-or-later | `aeb79a573b67f755b4f27f98df9af96852e98878` |
| libcrypto3, libssl3 | 3.3.7-r0 | Apache-2.0 | `a88fd8f44ad58cbeb9631a5dd3a0ec51a6e38c76` |

The `c:` field in `PACKAGES` records the Alpine aports revision for each
package, including its APKBUILD, patches and upstream source locations. Browse
those revisions at `https://github.com/alpinelinux/aports/tree/<revision>/main/`
and the corresponding package directory (wpa_supplicant, musl, libnl3,
pcsc-lite, dbus or openssl). These recipes are references, not a replacement
for providing complete corresponding source code where required.

The programs and libraries are dynamically linked, and shared libraries are
distributed separately to permit replacement. The binary archive does not
contain source. The separate `wifi-tools-sources.tgz` contains the exact
upstream source archives and Alpine recipe inputs identified by the revisions
above, verified against each APKBUILD's SHA-512 checksums. It is built by
`build-sources.sh` and is published alongside the binary archive at:
https://github.com/PeterSuh-Q3/tcrp-addons/blob/main/wifi-tools/releases/wifi-tools-sources.tgz

Source availability is subject to publication of that archive. Users may
replace the shared LGPL library; retain these notices when redistributing.
