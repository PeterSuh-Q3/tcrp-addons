#!/bin/sh
# Reconstruct the source inputs of the exact reviewed Alpine binary packages.
set -eu
cd "$(dirname "$0")"
dest=${1:-"$PWD/releases/wifi-tools-sources.tgz"}
scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT HUP INT TERM
for entry in \
 'wpa_supplicant:04dce289411f1f794e0d7e9a43d4b7a908d2bf5b' \
 'musl:b3006413508380c8a4e224006ef44c8394ca8c50' \
 'libnl3:7073e8a28972fc9da78a7b9147b473e0299997ee' \
 'pcsc-lite:e17d150a99904da928b6fda8d95a1e2b5d40c934' \
 'dbus:aeb79a573b67f755b4f27f98df9af96852e98878' \
 'openssl:a88fd8f44ad58cbeb9631a5dd3a0ec51a6e38c76'; do
 package=${entry%:*}; revision=${entry#*:}
 dir="$scratch/$package"
 mkdir -p "$dir"
 base="https://raw.githubusercontent.com/alpinelinux/aports/$revision/main/$package"
 curl -fLsS --retry 3 "$base/APKBUILD" -o "$dir/APKBUILD"
 printf '%s\n' "$revision" > "$dir/APORTS-REVISION"
 awk '/^sha512sums="/ {active=1;next} active && /^"/ {exit} active && NF==2 {print $1 " " $2}' "$dir/APKBUILD" > "$dir/SHA512SUMS"
 [ -s "$dir/SHA512SUMS" ] || { echo "Missing checksums: $package" >&2; exit 1; }
 while read -r checksum name; do
   case "$name" in
     *.tar.gz|*.tar.xz|*.tar.bz2|*.tar.zst)
       url="https://distfiles.alpinelinux.org/distfiles/v3.20/$name" ;;
     *) url="$base/$name" ;;
   esac
   curl -fLsS --retry 3 "$url" -o "$dir/$name"
 done < "$dir/SHA512SUMS"
 (cd "$dir" && sha512sum -c SHA512SUMS)
done
cp THIRD-PARTY-NOTICES.md "$scratch/THIRD-PARTY-NOTICES.md"
tar -czf "$dest" -C "$scratch" .
echo "Created $dest"
