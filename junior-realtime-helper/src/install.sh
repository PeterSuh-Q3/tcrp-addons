#!/bin/sh
# Copyright (C) 2026 PeterSuh-Q3. See repository LICENSE.
# Started by the Redpill on_patches hook inside DSM junior.
[ "$1" = patches ] || exit 0
[ -x /linuxrc.syno ] || exit 0
[ -e /tmp/junior-realtime-helper.pid ] && kill -0 "$(cat /tmp/junior-realtime-helper.pid)" 2>/dev/null && exit 0
ADDON_DIR=/exts/junior-realtime-helper
[ -r "$ADDON_DIR/selftest.sh" ] || exit 1
if [ -f "$ADDON_DIR/kms-display" ]; then
    chmod 755 "$ADDON_DIR/kms-display" 2>/dev/null || :
fi
(trap '' HUP; exec /bin/sh "$ADDON_DIR/selftest.sh" </dev/null >>/var/log/junior-realtime-helper.log 2>&1) &
echo "$!" >/tmp/junior-realtime-helper.pid
exit 0
