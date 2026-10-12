#!/bin/sh
# Copyright (C) 2026 PeterSuh-Q3. See repository LICENSE.
# Started by the Redpill on_patches hook inside DSM junior.
[ "$1" = patches ] || exit 0
[ -x /linuxrc.syno ] || exit 0
[ -e /tmp/junior-selftest.pid ] && kill -0 "$(cat /tmp/junior-selftest.pid)" 2>/dev/null && exit 0
ADDON_DIR=/exts/junior-selftest
[ -r "$ADDON_DIR/selftest.sh" ] || exit 1
(trap '' HUP; exec /bin/sh "$ADDON_DIR/selftest.sh" </dev/null >>/var/log/junior-selftest.log 2>&1) &
echo "$!" >/tmp/junior-selftest.pid
exit 0
