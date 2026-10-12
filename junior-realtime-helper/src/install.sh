#!/bin/sh
# Copyright (C) 2026 PeterSuh-Q3. See repository LICENSE.
# Redpill invokes this installer only from on_patches in the DSM junior root.
[ "$1" = patches ] || exit 0
[ -x /linuxrc.syno ] || exit 0

ADDON_DIR=/exts/junior-realtime-helper
[ -r "$ADDON_DIR/selftest.sh" ] || ADDON_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
[ -r "$ADDON_DIR/selftest.sh" ] || exit 0

if [ -r /tmp/junior-realtime-helper.pid ] &&
   kill -0 "$(cat /tmp/junior-realtime-helper.pid 2>/dev/null)" 2>/dev/null; then
    exit 0
fi

[ -f "$ADDON_DIR/kms-display" ] && chmod 755 "$ADDON_DIR/kms-display" 2>/dev/null || :
(trap '' HUP; exec /bin/sh "$ADDON_DIR/selftest.sh" </dev/null >>/var/log/junior-realtime-helper.log 2>&1) &
echo "$!" >/tmp/junior-realtime-helper.pid
exit 0
