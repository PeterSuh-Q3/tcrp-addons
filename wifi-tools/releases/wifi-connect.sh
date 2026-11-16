#!/bin/sh
set +x
umask 077
[ -s /addons/mshell-wifi.conf ] || exit 0
mkdir /run/mshell-wifi.lock 2>/dev/null || exit 0
trap 'rmdir /run/mshell-wifi.lock 2>/dev/null' EXIT
runtime=$(mktemp -d /run/mshell-wifi.XXXXXX) || exit 1
tar -xzf /exts/wifi-tools/wifi-tools.tgz -C "$runtime" || exit 1
wpa="$runtime/bin/wpa_supplicant"
count=0
while [ "$count" -lt 150 ]; do
    for path in /sys/class/net/*/phy80211; do
        [ -e "$path" ] || continue
        iface=${path%/phy80211}; iface=${iface##*/}
        case "$iface" in p2p*) continue ;; esac
        # Never take over an interface already managed by another supplicant.
        [ ! -S "/var/run/wpa_supplicant/$iface" ] || exit 0
        [ ! -s /run/mshell-wifi.pid ] || exit 0
        ip link set "$iface" up || exit 1
        "$runtime/lib/ld-musl-x86_64.so.1" --library-path "$runtime/lib" "$wpa" -q -B -D nl80211 -i "$iface" -c /addons/mshell-wifi.conf -P /run/mshell-wifi.pid >/dev/null 2>&1 || {
            logger -t mshell-wifi 'Wireless authentication service failed to start'
            exit 1
        }
        logger -t mshell-wifi 'Wireless authentication service started; DHCP is managed by DSM'
        exit 0
    done
    sleep 2
    count=$((count + 1))
done
logger -t mshell-wifi 'No wireless interface appeared within 300 seconds'
