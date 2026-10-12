#!/bin/sh
# DSM systemd entry point. The process is supervised by systemd and runs as root.
LOCK_DIR=/var/run/junior-realtime-helper

# The junior monitor may overlap briefly with systemd while DSM switches roots.
# Wait for its owner to exit, or clear a stale lock left by the root transition.
while [ -d "$LOCK_DIR" ]; do
    owner=$(cat "$LOCK_DIR/pid" 2>/dev/null)
    if [ -n "$owner" ] && kill -0 "$owner" 2>/dev/null; then
        sleep 2
        continue
    fi
    rm -f "$LOCK_DIR/pid"
    rmdir "$LOCK_DIR" 2>/dev/null || sleep 1
done

exec /bin/sh /usr/syno/sbin/junior-realtime-helper/selftest.sh
