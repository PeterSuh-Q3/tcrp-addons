#!/bin/sh
# Copyright (C) 2026 PeterSuh-Q3. See repository LICENSE.
# jrExit runs for every linuxrc Exit(); only recognized junior cases start us.
# The late event stages a systemd service so DSM can track the monitor process.

ADDON_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
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
    (trap '' HUP; exec /bin/sh "$MONITOR_DIR/selftest.sh" </dev/null >/dev/null 2>&1) &
    echo "$!" >"$PID_FILE"
}

remove_managed_path() {
    path=$1
    if [ -e "$path" ] || [ -L "$path" ]; then
        rm -f "$path"
        echo "junior-realtime-helper: removed stale startup path $path"
    fi
}

remove_dsm_service() {
    root=$1
    remove_managed_path "$root/usr/lib/systemd/system/junior-realtime-helper.service"
    remove_managed_path "$root/usr/lib/systemd/system/multi-user.target.wants/junior-realtime-helper.service"
    remove_managed_path "$root/etc/systemd/system/junior-realtime-helper.service"
    remove_managed_path "$root/etc/systemd/system/multi-user.target.wants/junior-realtime-helper.service"
    remove_managed_path "$root/usr/local/etc/rc.d/S99junior-realtime-helper.sh"
}

stage_dsm_service() {
    root=${TMPROOT:-/tmpRoot}
    version_file=$root/etc.defaults/VERSION
    [ -r "$version_file" ] || version_file=$root/etc/VERSION
    [ -r "$version_file" ] || { echo 'junior-realtime-helper: DSM VERSION not found under /tmpRoot' >&2; exit 0; }

    major=$(awk -F= '$1 == "majorversion" || $1 == "major" {gsub(/"/, "", $2); print $2; exit}' "$version_file")
    if [ "$major" = 6 ]; then
        remove_dsm_service "$root"
        echo 'junior-realtime-helper: DSM 6 late systemd service skipped'
        exit 0
    fi
    [ "$major" = 7 ] || { echo "junior-realtime-helper: DSM major $major is unsupported" >&2; exit 0; }

    payload_dir=
    for candidate in "$ADDON_DIR/junior-realtime-helper" /exts/junior-realtime-helper "$ADDON_DIR"; do
        if [ -r "$candidate/selftest.sh" ] && [ -r "$candidate/dsm-launch.sh" ] && [ -f "$candidate/kms-display" ]; then
            payload_dir=$candidate
            break
        fi
    done
    [ -n "$payload_dir" ] || {
        echo 'junior-realtime-helper: selftest.sh, dsm-launch.sh, and kms-display payload not found under /exts' >&2
        exit 1
    }

    appdir=$root/usr/local/lib/junior-realtime-helper
    unitdir=$root/usr/lib/systemd/system
    wants=$unitdir/multi-user.target.wants

    # Remove prior startup mechanisms first so an older rc.d script or an
    # /etc systemd override cannot shadow or duplicate this managed service.
    remove_dsm_service "$root"
    mkdir -p "$appdir" "$unitdir" "$wants" || exit 1
    cp "$payload_dir/selftest.sh" "$appdir/selftest.sh" || exit 1
    cp "$payload_dir/dsm-launch.sh" "$appdir/dsm-launch.sh" || exit 1
    cp "$payload_dir/kms-display" "$appdir/kms-display" || exit 1
    chmod 755 "$appdir/selftest.sh" "$appdir/dsm-launch.sh" "$appdir/kms-display"

    cat >"$unitdir/junior-realtime-helper.service" <<'EOF'
[Unit]
Description=MSHELL addon Junior realtime helper
After=synoscgi.service nginx.service

[Service]
Type=simple
ExecStart=/bin/sh /usr/local/lib/junior-realtime-helper/dsm-launch.sh
Restart=no
KillMode=control-group
TimeoutStopSec=15

[Install]
WantedBy=multi-user.target
EOF
    chmod 644 "$unitdir/junior-realtime-helper.service"
    ln -sf /usr/lib/systemd/system/junior-realtime-helper.service "$wants/junior-realtime-helper.service"
    echo "junior-realtime-helper: DSM $major systemd service staged under $root"
}

case "$1" in
    jrExit) start_junior_monitor ;;
    late) stage_dsm_service ;;
    *) exit 0 ;;
esac
