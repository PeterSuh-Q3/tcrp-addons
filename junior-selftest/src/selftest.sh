#!/bin/sh
# Copyright (C) 2026 PeterSuh-Q3. See repository LICENSE.
# Read-only junior status monitor. Never mounts, formats or writes a disk.
export PATH=/usr/syno/bin:/usr/syno/sbin:/usr/bin:/usr/sbin:/bin:/sbin
trap '' HUP
CONSOLE=/dev/tty1
active_console=$(cat /sys/devices/virtual/tty/tty0/active 2>/dev/null)
case "$active_console" in tty[0-9]*) [ -c "/dev/$active_console" ] && CONSOLE="/dev/$active_console" ;; esac

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

render_status() {
    [ -c "$CONSOLE" ] || return 1
    {
        printf '\033[s\033[H'
        row=0
        while [ "$row" -lt 14 ]; do
            printf '\033[2K\r\n'
            row=$((row + 1))
        done
        printf '\033[H'
        printf '\033[2KREDPILL JUNIOR SELFTEST\r\n'
        printf '\033[2KMODEL SA6400 DSM 7.4.1\r\n'
        printf '\033[2KIP %s\r\n' "$ip"
        printf '\033[2KTCP 5000 %s\r\n' "$port"
        printf '\033[2KRECOGNIZED DISKS %s\r\n' "$count"
        printf '\033[2KDEVICE  SIZE   MODEL\r\n'
        shown=0
        printf '%s\n' "$disks" | while IFS= read -r disk; do
            [ -n "$disk" ] || continue
            [ "$shown" -lt 8 ] || break
            printf '\033[2K%s\r\n' "$disk"
            shown=$((shown + 1))
        done
        printf '\033[u'
    } >"$CONSOLE"
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
    render_status || printf 'junior-selftest: cannot write %s\n' "$CONSOLE" >&2
    sleep 10
done
