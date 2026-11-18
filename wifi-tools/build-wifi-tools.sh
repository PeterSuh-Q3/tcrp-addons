#!/bin/sh
# Build an isolated x86-64 musl runtime; do not install libraries into DSM.
set -eu
cd "$(dirname "$0")"
docker run --rm --platform linux/amd64 -v "$PWD:/output" alpine:3.20 sh -ec '
 apk add --no-cache wpa_supplicant
 mkdir -p /bundle/bin /bundle/lib /bundle/licenses
 cp /sbin/wpa_supplicant /sbin/wpa_passphrase /sbin/wpa_cli /bundle/bin/
 for lib in /lib/ld-musl-x86_64.so.1 /lib/libcrypto.so.3 /lib/libssl.so.3 /usr/lib/libnl-3.so.200 /usr/lib/libnl-genl-3.so.200 /usr/lib/libpcsclite.so.1 /usr/lib/libdbus-1.so.3; do
   cp -L "$lib" /bundle/lib/
 done
 cp /lib/apk/db/installed /bundle/PACKAGES
 cp -a /output/licenses/. /bundle/licenses/
 cp /output/THIRD-PARTY-NOTICES.md /bundle/THIRD-PARTY-NOTICES.md
 for spec in wpa_supplicant:2.10-r11 musl:1.2.5-r3 libnl3:3.9.0-r1 pcsc-lite-libs:2.2.3-r0 dbus-libs:1.14.10-r1 libcrypto3:3.3.7-r0 libssl3:3.3.7-r0; do
   package=${spec%:*}; version=${spec#*:}
   apk info -e "$package=$version" >/dev/null || { echo "Unreviewed package version: $package" >&2; exit 1; }
 done
 # Record the installed binary package metadata for provenance.
 apk info -a > /bundle/PACKAGE-INFO
 /bundle/lib/ld-musl-x86_64.so.1 --library-path /bundle/lib /bundle/bin/wpa_supplicant -v
 /bundle/lib/ld-musl-x86_64.so.1 --library-path /bundle/lib /bundle/bin/wpa_cli -v
 tar -czf /output/releases/wifi-tools.tgz -C /bundle .
'
