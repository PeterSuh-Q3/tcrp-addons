#!/bin/sh
# Copyright (C) 2026 PeterSuh-Q3. See repository LICENSE.
# jrExit runs for every linuxrc Exit(); only recognized junior cases start us.
# The late event stages an rc.d hook so DSM starts the monitor after its normal
# boot sequence has brought up userspace and the DRM device.

ADDON_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
LOG=/var/log/junior-realtime-helper.log

start_junior_monitor() {
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
    if grep -Fq 'Exit on error [9] force_junior bootargs detected' "$JUNIOR_REASON" 2>/dev/null; then
        junior_reason_match=1
    fi
    [ "$junior_reason_match" -eq 1 ] || exit 0
    [ -x /linuxrc.syno ] || exit 0

    MONITOR_DIR=/exts/junior-realtime-helper
    [ -r "$MONITOR_DIR/selftest.sh" ] || MONITOR_DIR=$ADDON_DIR
    [ -r "$MONITOR_DIR/selftest.sh" ] || exit 0

    PID_FILE=/tmp/junior-realtime-helper.pid
    if [ -r "$PID_FILE" ] && kill -0 "$(cat "$PID_FILE" 2>/dev/null)" 2>/dev/null; then
        exit 0
    fi

    [ -f "$MONITOR_DIR/kms-display" ] && chmod 755 "$MONITOR_DIR/kms-display" 2>/dev/null || :
    (trap '' HUP; exec /bin/sh "$MONITOR_DIR/selftest.sh" </dev/null >>"$LOG" 2>&1) &
    echo "$!" >"$PID_FILE"
}

remove_dsm_service() {
    root=$1
    rm -f "$root/usr/lib/systemd/system/junior-realtime-helper.service"
    rm -f "$root/usr/lib/systemd/system/multi-user.target.wants/junior-realtime-helper.service"
    rm -f "$root/usr/local/etc/rc.d/S99junior-realtime-helper.sh"
}

stage_dsm_rc_hook() {
    root=${TMPROOT:-/tmpRoot}
    version_file=$root/etc.defaults/VERSION
    [ -r "$version_file" ] || version_file=$root/etc/VERSION
    [ -r "$version_file" ] || { echo 'junior-realtime-helper: DSM VERSION not found under /tmpRoot' >&2; exit 0; }

    major=$(awk -F= '$1 == "majorversion" || $1 == "major" {gsub(/"/, "", $2); print $2; exit}' "$version_file")
    if [ "$major" = 6 ]; then
        remove_dsm_service "$root"
        echo 'junior-realtime-helper: DSM 6 late rc.d hook skipped'
        exit 0
    fi
    [ "$major" = 7 ] || { echo "junior-realtime-helper: DSM major $major is unsupported" >&2; exit 0; }

    payload_dir=
    for candidate in "$ADDON_DIR/junior-realtime-helper" /exts/junior-realtime-helper "$ADDON_DIR"; do
        if [ -r "$candidate/selftest.sh" ] && [ -f "$candidate/kms-display" ]; then
            payload_dir=$candidate
            break
        fi
    done
    [ -n "$payload_dir" ] || {
        echo 'junior-realtime-helper: selftest.sh and kms-display payload not found under /exts' >&2
        exit 1
    }

    appdir=$root/usr/local/lib/junior-realtime-helper
    rcdir=$root/usr/local/etc/rc.d
    mkdir -p "$appdir" "$rcdir" || exit 1
    cp "$payload_dir/selftest.sh" "$appdir/selftest.sh" || exit 1
    cp "$payload_dir/kms-display" "$appdir/kms-display" || exit 1
    chmod 755 "$appdir/selftest.sh" "$appdir/kms-display"

    cat >"$rcdir/S99junior-realtime-helper.sh" <<'EOF'
#!/bin/sh
# DSM rc.d hook: start only after DSM has entered its regular boot sequence.
APPDIR=/usr/local/lib/junior-realtime-helper
LOG=/var/log/junior-realtime-helper.log
PID_FILE=/tmp/junior-realtime-helper.pid

has_drm_card() {
    for card in /dev/dri/card[0-9]*; do
        [ -c "$card" ] && return 0
    done
    return 1
}

case "$1" in
    start|"")
        if [ -x /linuxrc.syno ]; then
            echo "$(date '+%H:%M:%S') rc.d: skipped; Junior is still active" >>"$LOG"
            exit 0
        fi
        if [ -r "$PID_FILE" ] && kill -0 "$(cat "$PID_FILE" 2>/dev/null)" 2>/dev/null; then
            exit 0
        fi
        # Some DRM drivers register their card after the rc.d boot pass starts.
        tries=0
        while ! has_drm_card && [ "$tries" -lt 60 ]; do
            sleep 2
            tries=$((tries + 1))
        done
        if ! has_drm_card; then
            echo "$(date '+%H:%M:%S') rc.d: skipped; no /dev/dri/card node appeared" >>"$LOG"
            exit 0
        fi
        if [ ! -r "$APPDIR/selftest.sh" ] || [ ! -x "$APPDIR/kms-display" ]; then
            echo "$(date '+%H:%M:%S') rc.d: helper payload is incomplete" >>"$LOG"
            exit 1
        fi
        (trap '' HUP; exec /bin/sh "$APPDIR/selftest.sh" </dev/null >>"$LOG" 2>&1) &
        echo "$!" >"$PID_FILE"
        echo "$(date '+%H:%M:%S') rc.d: DSM helper started (PID $(cat "$PID_FILE"))" >>"$LOG"
        ;;
    stop)
        if [ -r "$PID_FILE" ]; then
            pid=$(cat "$PID_FILE" 2>/dev/null)
            kill "$pid" 2>/dev/null || :
        fi
        ;;
esac
exit 0
EOF
    chmod 755 "$rcdir/S99junior-realtime-helper.sh"
    # Remove the earlier systemd unit so upgraded root images cannot start
    # duplicate monitor instances.
    rm -f "$root/usr/lib/systemd/system/junior-realtime-helper.service"
    rm -f "$root/usr/lib/systemd/system/multi-user.target.wants/junior-realtime-helper.service"
    echo "junior-realtime-helper: DSM $major rc.d hook staged under $root"
}

case "$1" in
    jrExit) start_junior_monitor ;;
    late) stage_dsm_rc_hook ;;
    *) exit 0 ;;
esac
