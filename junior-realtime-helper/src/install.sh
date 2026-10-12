#!/bin/sh
# Copyright (C) 2026 PeterSuh-Q3. See repository LICENSE.
# Redpill invokes this installer with `patches` at the junior hook and `late`
# at on_os_load, when /tmpRoot contains the DSM root filesystem.
ADDON_DIR=/exts/junior-realtime-helper
[ -r "$ADDON_DIR/selftest.sh" ] || ADDON_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
TMPROOT=${TMPROOT:-/tmpRoot}

start_junior_monitor() {
    [ -x /linuxrc.syno ] || return 0
    [ -r "$ADDON_DIR/selftest.sh" ] || return 0
    if [ -r /tmp/junior-realtime-helper.pid ] &&
       kill -0 "$(cat /tmp/junior-realtime-helper.pid 2>/dev/null)" 2>/dev/null; then
        return 0
    fi
    [ -f "$ADDON_DIR/kms-display" ] && chmod 755 "$ADDON_DIR/kms-display" 2>/dev/null || :
    (trap '' HUP; exec /bin/sh "$ADDON_DIR/selftest.sh" </dev/null >>/var/log/junior-realtime-helper.log 2>&1) &
    echo "$!" >/tmp/junior-realtime-helper.pid
}

install_dsm_monitor() {
    if [ ! -d "$TMPROOT/usr" ]; then
        echo "junior-realtime-helper: DSM root not mounted at $TMPROOT; skipping late install" >&2
        return 0
    fi
    DSM_VERSION_FILE="$TMPROOT/etc.defaults/VERSION"
    [ -r "$DSM_VERSION_FILE" ] || DSM_VERSION_FILE="$TMPROOT/etc/VERSION"
    DSM_MAJOR=$(awk -F= '$1 == "productversion" {gsub(/"/, "", $2); split($2, v, "."); print v[1]; exit}' "$DSM_VERSION_FILE" 2>/dev/null)
    case "$DSM_MAJOR" in
        7|8|9|[1-9][0-9]*) ;;
        *)
            echo "junior-realtime-helper: DSM-stage service requires DSM 7 or later; skipping (DSM ${DSM_MAJOR:-unknown})"
            return 0
            ;;
    esac

    if [ ! -r "$ADDON_DIR/selftest.sh" ] || [ ! -f "$ADDON_DIR/kms-display" ] ||
       [ ! -r "$ADDON_DIR/dsm-start.sh" ] || [ ! -r "$ADDON_DIR/junior-realtime-helper.service" ]; then
        echo "junior-realtime-helper: DSM monitor payload missing from $ADDON_DIR; skipping late install" >&2
        return 0
    fi

    DEST="$TMPROOT/usr/syno/sbin/junior-realtime-helper"
    mkdir -p "$DEST" "$TMPROOT/var/log" || return 0
    cp -f "$ADDON_DIR/selftest.sh" "$DEST/selftest.sh" || return 0
    cp -f "$ADDON_DIR/kms-display" "$DEST/kms-display" || return 0
    cp -f "$ADDON_DIR/dsm-start.sh" "$DEST/dsm-start.sh" || return 0
    chmod 755 "$DEST/selftest.sh" "$DEST/kms-display" "$DEST/dsm-start.sh" || return 0

    UNIT_DIR="$TMPROOT/usr/lib/systemd/system"
    WANTS_DIR="$UNIT_DIR/multi-user.target.wants"
    mkdir -p "$WANTS_DIR" || return 0
    cp -f "$ADDON_DIR/junior-realtime-helper.service" "$UNIT_DIR/junior-realtime-helper.service" || return 0
    chmod 644 "$UNIT_DIR/junior-realtime-helper.service"
    ln -sf /usr/lib/systemd/system/junior-realtime-helper.service \
        "$WANTS_DIR/junior-realtime-helper.service"
    echo "junior-realtime-helper: DSM monitor installed under $TMPROOT (DSM ${DSM_MAJOR:-unknown})"
    return 0
}

case "$1" in
    patches) start_junior_monitor ;;
    late) install_dsm_monitor ;;
    *) exit 0 ;;
esac
exit 0
