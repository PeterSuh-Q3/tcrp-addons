#!/bin/sh
# Copyright (C) 2026 PeterSuh-Q3. See repository LICENSE.
# Read-only junior status monitor. Never mounts, formats or writes a disk.
export PATH=/usr/syno/bin:/usr/syno/sbin:/usr/bin:/usr/sbin:/bin:/sbin
trap '' HUP
LOG=/tmp/junior-selftest.log
fb_ok=1

addresses() {
    ip -o -4 addr show scope global 2>/dev/null |
        awk '{split($4, a, "/"); if ($2 != "lo") print a[1]}' |
        sort -u
}

disk_list() {
    for path in /sys/block/sd* /sys/block/sata* /sys/block/nvme*n* /sys/block/vd*; do
        [ -e "$path/size" ] || continue
        name=${path##*/}
        case "$name" in *[!a-zA-Z0-9]*) continue ;; esac
        sectors=$(cat "$path/size" 2>/dev/null) || continue
        [ "$sectors" -gt 0 ] 2>/dev/null || continue
        model=$(cat "$path/device/model" 2>/dev/null | tr -cd '[:alnum:] ._-')
        mb=$((sectors / 2048))
        printf '%s %sMB %s\n' "$name" "$mb" "$model"
    done
}

port_ready() {
    # Probe the local listener or web root without triggering installation.
    for probe in /bin/nc /usr/bin/nc /usr/syno/bin/nc; do
        [ -x "$probe" ] || continue
        "$probe" -z -w 2 "$1" 5000 </dev/null >/dev/null 2>&1 && return 0
    done
    for probe in /bin/curl /usr/bin/curl /usr/syno/bin/curl; do
        [ -x "$probe" ] || continue
        "$probe" -sS -o /dev/null --connect-timeout 2 --max-time 3 \
            "http://$1:5000/" >/dev/null 2>&1 && return 0
    done
    return 1
}

previous=''
while :; do
    ips=$(addresses)
    disks=$(disk_list)
    count=$(printf '%s\n' "$disks" | awk 'NF {n++} END {print n+0}')
    ip=WAITING
    port=WAITING
    if [ -n "$ips" ]; then
        ip=$(printf '%s\n' "$ips" | head -n 1)
        port=CLOSED
        port_ready "$ip" && port=READY
    fi
    current=$(printf 'ip=%s tcp5000=%s kernel_disks=%s\n%s' \
        "$ip" "$port" "$count" "$disks")
    if [ "$current" != "$previous" ]; then
        printf '%s\n' "$current"
        previous=$current
    fi
    if [ "$fb_ok" -eq 1 ]; then
        set -- 'REDPILL JUNIOR SELFTEST' 'MODEL SA6400 DSM 7.4.1' \
            "IP $ip" "TCP 5000 $port" "KERNEL DISKS $count"
        shown=0
        printf '%s\n' "$disks" >/tmp/junior-selftest.disks
        while IFS= read -r disk; do
            [ -n "$disk" ] || continue
            [ "$shown" -lt 3 ] || break
            set -- "$@" "$disk"
            shown=$((shown + 1))
        done </tmp/junior-selftest.disks
        /tmp/junior-fb-status "$@" 2>>"$LOG" || fb_ok=0
    fi
    sleep 10
done
