#!/usr/bin/env bash
set -euo pipefail

# Rebuild the checked-in usr tree on Linux with GNU tar.
here=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
source_dir="${here}/usr"
binary="${here}/usr/sbin/busybox-static"
output=${1:-"${here}/usr.tgz.new"}
expected=2571bdcaa3bc1bcc0b5d01c71d1c3b9ed21981f6bf1e98c458a86551cbd4545c

[[ $(uname -s) == Linux ]] || { echo 'Linux is required' >&2; exit 1; }
tar --version | head -1 | grep -q 'GNU tar' || { echo 'GNU tar is required' >&2; exit 1; }
[[ -d "$source_dir" && -f "$binary" ]] || { echo 'Missing usr tree or busybox-static' >&2; exit 1; }
[[ $(sha256sum "$binary" | awk '{print $1}') == "$expected" ]] || { echo 'Unexpected busybox-static SHA-256' >&2; exit 1; }
[[ "$output" != "${here}/usr.tgz" ]] || { echo 'Use a staged output, not usr.tgz' >&2; exit 1; }

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
mkdir "$tmp/tree" "$tmp/check"
umask 022
cp -a "$source_dir" "$tmp/tree/usr"
find "$tmp/tree/usr" -name .DS_Store -type f -delete
diff -r --no-dereference --exclude=.DS_Store "$source_dir" "$tmp/tree/usr" >/dev/null
chmod 0755 "$tmp/tree/usr/sbin/busybox-static"
# Clear unsafe write/set-ID bits without changing the executable bits of files.
find "$tmp/tree" -type d -exec chmod 0755 {} +
find "$tmp/tree" -type f -exec chmod go-w,u-s,g-s {} +
mkdir -p "$(dirname "$output")"
tar -C "$tmp/tree" --sort=name --format=gnu --mtime='@0' --owner=0 --group=0 --numeric-owner -cf - ./usr | gzip -n > "$tmp/usr.tgz"
gzip -t "$tmp/usr.tgz"
tar -xzf "$tmp/usr.tgz" --no-same-owner -C "$tmp/check"
diff -r --no-dereference "$tmp/tree/usr" "$tmp/check/usr" >/dev/null
[[ $(sha256sum "$tmp/check/usr/sbin/busybox-static" | awk '{print $1}') == "$expected" ]]
[[ $(stat -c '%a' "$tmp/check/usr/sbin/busybox-static") == 755 ]]
tar -tvzf "$tmp/usr.tgz" --numeric-owner | awk '$2 != "0/0" {exit 1}' || { echo 'Archive ownership is not root:root' >&2; exit 1; }
cp "$tmp/usr.tgz" "$output"
sha256sum "$output"
