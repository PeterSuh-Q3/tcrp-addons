#!/bin/sh
# DSM systemd entry point. Junior mode continues to use the on_jrExit hook.
APPDIR=/usr/local/lib/junior-realtime-helper
PID_FILE=/tmp/junior-realtime-helper.pid

if [ -x /linuxrc.syno ]; then
    echo 'junior-realtime-helper: skipped; Junior is still active'
    exit 0
fi

if [ -r "$PID_FILE" ] && kill -0 "$(cat "$PID_FILE" 2>/dev/null)" 2>/dev/null; then
    echo 'junior-realtime-helper: skipped; helper process is already running'
    exit 0
fi

has_drm_card() {
    for card in /dev/dri/card[0-9]*; do
        [ -c "$card" ] && return 0
    done
    return 1
}

# DRM nodes can appear after DSM starts its regular service target.
tries=0
while ! has_drm_card && [ "$tries" -lt 60 ]; do
    sleep 2
    tries=$((tries + 1))
done
if ! has_drm_card; then
    echo 'junior-realtime-helper: skipped; no /dev/dri/card node appeared after 120 seconds'
    exit 0
fi

if [ ! -r "$APPDIR/selftest.sh" ] || [ ! -x "$APPDIR/kms-display" ]; then
    echo 'junior-realtime-helper: failed; helper payload is incomplete'
    exit 1
fi

echo 'junior-realtime-helper: starting DSM helper'
exec /bin/sh "$APPDIR/selftest.sh" </dev/null >/dev/null 2>&1
