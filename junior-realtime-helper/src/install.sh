#!/bin/sh
# Copyright (C) 2026 PeterSuh-Q3. See repository LICENSE.
# jrExit runs for every linuxrc Exit(); only recognized junior cases start us.
# The late event stages a DSM service so the DRM display can continue after
# DSM takes over the root filesystem.

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
}

stage_dsm_service() {
    root=${TMPROOT:-/tmpRoot}
    version_file=$root/etc.defaults/VERSION
    [ -r "$version_file" ] || version_file=$root/etc/VERSION
    [ -r "$version_file" ] || { echo 'junior-realtime-helper: DSM VERSION not found under /tmpRoot' >&2; exit 0; }

    major=$(awk -F= '$1 == "majorversion" || $1 == "major" {gsub(/"/, "", $2); print $2; exit}' "$version_file")
    if [ "$major" = 6 ]; then
        remove_dsm_service "$root"
        echo 'junior-realtime-helper: DSM 6 late service skipped'
        exit 0
    fi
    [ "$major" = 7 ] || { echo "junior-realtime-helper: DSM major $major is unsupported" >&2; exit 0; }

    [ -r "$ADDON_DIR/selftest.sh" ] && [ -f "$ADDON_DIR/kms-display" ] || {
        echo "junior-realtime-helper: addon payload not found in $ADDON_DIR" >&2
        exit 0
    }

    appdir=$root/usr/local/lib/junior-realtime-helper
    unitdir=$root/usr/lib/systemd/system
    wants=$unitdir/multi-user.target.wants
    mkdir -p "$appdir" "$unitdir" "$wants" || exit 0
    cp "$ADDON_DIR/selftest.sh" "$appdir/selftest.sh" || exit 0
    cp "$ADDON_DIR/kms-display" "$appdir/kms-display" || exit 0
    chmod 755 "$appdir/selftest.sh" "$appdir/kms-display"

    cat >"$unitdir/junior-realtime-helper.service" <<'EOF'
[Unit]
Description=Junior Realtime Helper DRM display
After=systemd-udev-settle.service

[Service]
Type=simple
ExecStart=/bin/sh -c 'exec /bin/sh /usr/local/lib/junior-realtime-helper/selftest.sh >>/var/log/junior-realtime-helper.log 2>&1'
Restart=on-failure
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF
    ln -sf ../junior-realtime-helper.service "$wants/junior-realtime-helper.service"
    echo "junior-realtime-helper: DSM $major service staged under $root"
}

case "$1" in
    jrExit) start_junior_monitor ;;
    late) stage_dsm_service ;;
    *) exit 0 ;;
esac
