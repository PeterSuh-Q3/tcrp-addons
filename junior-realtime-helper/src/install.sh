#!/bin/sh
# Copyright (C) 2026 PeterSuh-Q3. See repository LICENSE.
# Redpill invokes this installer only from on_patches in the DSM junior root.
[ "$1" = patches ] || exit 0
[ -x /linuxrc.syno ] || exit 0

ADDON_DIR=/exts/junior-realtime-helper
[ -r "$ADDON_DIR/selftest.sh" ] || ADDON_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
MONITOR_PID_FILE=/tmp/junior-realtime-helper.pid
KMS_PID_FILE=/tmp/junior-realtime-helper-kms.pid
LOCK_PID_FILE=/var/run/junior-realtime-helper/pid

start_junior_monitor() {
    [ -x /linuxrc.syno ] || return 0
    [ -r "$ADDON_DIR/selftest.sh" ] || return 0
    if [ -r "$MONITOR_PID_FILE" ] &&
       kill -0 "$(cat "$MONITOR_PID_FILE" 2>/dev/null)" 2>/dev/null; then
        return 0
    fi

    [ -f "$ADDON_DIR/kms-display" ] && chmod 755 "$ADDON_DIR/kms-display" 2>/dev/null || :
    (trap '' HUP; exec /bin/sh "$ADDON_DIR/selftest.sh" </dev/null >>/var/log/junior-realtime-helper.log 2>&1) &
    echo "$!" >"$MONITOR_PID_FILE"
}

stop_junior_monitor() {
    [ -r "$MONITOR_PID_FILE" ] || return 0
    monitor_pid=$(cat "$MONITOR_PID_FILE" 2>/dev/null)
    case "$monitor_pid" in ''|*[!0-9]*) return 0 ;; esac
    owner_pid=$(cat "$LOCK_PID_FILE" 2>/dev/null)
    if [ "$owner_pid" != "$monitor_pid" ]; then
        rm -f "$MONITOR_PID_FILE"
        return 0
    fi
    kill -0 "$monitor_pid" 2>/dev/null || {
        rm -f "$MONITOR_PID_FILE" "$KMS_PID_FILE"
        return 0
    }

    echo "junior-realtime-helper: stopping junior display before DSM root handoff"
    kill -TERM "$monitor_pid" 2>/dev/null || :
    kms_pid=$(cat "$KMS_PID_FILE" 2>/dev/null)
    case "$kms_pid" in ''|*[!0-9]*) ;; *) kill -TERM "$kms_pid" 2>/dev/null || : ;; esac

    attempt=0
    while kill -0 "$monitor_pid" 2>/dev/null; do
        [ "$attempt" -lt 10 ] || {
            echo "junior-realtime-helper: monitor did not exit before DSM handoff" >&2
            return 0
        }
        attempt=$((attempt + 1))
        sleep 1
    done
    rm -f "$MONITOR_PID_FILE" "$KMS_PID_FILE"
    echo "junior-realtime-helper: junior display released"
}

case "$1" in
    patches) start_junior_monitor ;;
    late) stop_junior_monitor ;;
    *) exit 0 ;;
esac
exit 0
