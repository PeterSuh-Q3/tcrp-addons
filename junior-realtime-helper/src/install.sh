#!/bin/sh
# Copyright (C) 2026 PeterSuh-Q3. See repository LICENSE.
# jrExit runs for every linuxrc Exit(); only the junior fallback reason starts us.
[ "$1" = jrExit ] || exit 0

# MSHELL Manager persists this opt-out in the loader kernel command line.
# Absence keeps the addon's historical enabled-by-default behavior.
grep -Eq '(^|[[:space:]])junior-realtime-helper=0([[:space:]]|$)' /proc/cmdline 2>/dev/null && exit 0

JUNIOR_REASON=/var/log/junior_reason
junior_reason_match=0
if grep -Fq 'Exit on error [12]' "$JUNIOR_REASON" 2>/dev/null &&
    grep -Fq 'go to junior mode' "$JUNIOR_REASON" 2>/dev/null; then
    junior_reason_match=1
fi
if grep -Fq 'Exit on error [7]' "$JUNIOR_REASON" 2>/dev/null &&
    grep -Fq 'root not matched with junior' "$JUNIOR_REASON" 2>/dev/null; then
    junior_reason_match=1
fi
[ "$junior_reason_match" -eq 1 ] || exit 0
[ -x /linuxrc.syno ] || exit 0

ADDON_DIR=/exts/junior-realtime-helper
[ -r "$ADDON_DIR/selftest.sh" ] || ADDON_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
[ -r "$ADDON_DIR/selftest.sh" ] || exit 0

PID_FILE=/tmp/junior-realtime-helper.pid
if [ -r "$PID_FILE" ] && kill -0 "$(cat "$PID_FILE" 2>/dev/null)" 2>/dev/null; then
    exit 0
fi

[ -f "$ADDON_DIR/kms-display" ] && chmod 755 "$ADDON_DIR/kms-display" 2>/dev/null || :
(trap '' HUP; exec /bin/sh "$ADDON_DIR/selftest.sh" </dev/null >>/var/log/junior-realtime-helper.log 2>&1) &
echo "$!" >"$PID_FILE"
exit 0
