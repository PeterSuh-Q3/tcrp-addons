#!/bin/sh
set +x
umask 077

CONFIG=/addons/mshell-wifi.conf
[ -s "$CONFIG" ] || exit 0
mkdir /run/mshell-wifi.lock 2>/dev/null || exit 0

runtime=/run/mshell-wifi.$$
mountpoint=/run/mshell-wifi-p3.$$
mounted=0
mkdir "$runtime" || { rmdir /run/mshell-wifi.lock 2>/dev/null; exit 1; }

cleanup() {
    [ "$mounted" -ne 1 ] || umount "$mountpoint" >/dev/null 2>&1 || true
    [ "$mounted" -ne 1 ] || rmdir "$mountpoint" 2>/dev/null || true
    rmdir "$runtime" 2>/dev/null || true
    rmdir /run/mshell-wifi.lock 2>/dev/null || true
}
trap cleanup EXIT HUP INT TERM

tar -xzf /exts/wifi-tools/wifi-tools.tgz -C "$runtime" || exit 1
wpa="$runtime/bin/wpa_supplicant"
wpa_log="$runtime/wpa_supplicant.log"
diag="$runtime/diagnostics.txt"
iface=
started=0

log() {
    logger -t mshell-wifi "$1" 2>/dev/null || true
}

capture_diagnostics() {
    {
        echo "Wi-Fi diagnostic capture: $(date 2>/dev/null || echo unknown)"
        echo "SSID credentials intentionally excluded."
        echo "WPA supplicant config present: $([ -s "$CONFIG" ] && echo yes || echo no)"
        echo "Interface: ${iface:-not-found}"
        echo "Supplicant started: $started"
        if [ -n "$iface" ]; then
            echo "--- interface state ---"
            for f in address operstate carrier; do
                if [ -r "/sys/class/net/$iface/$f" ]; then
                    printf '%s=' "$f"
                    cat "/sys/class/net/$iface/$f" 2>/dev/null
                fi
            done
            echo "--- IPv4 address ---"
            ip -4 addr show dev "$iface" 2>&1 || ifconfig "$iface" 2>&1 || true
            echo "--- routes ---"
            ip route 2>&1 || route -n 2>&1 || true
        fi
        echo "--- wireless modules ---"
        lsmod 2>&1 | grep -E '(^| )(wl|cfg80211|brcmfmac|brcmutil|ccm|gcm|cmac)( |$)' || true
        echo "--- relevant kernel messages ---"
        dmesg 2>&1 | grep -iE 'wl|cfg80211|wifi|wpa|firmware|brcm|80211|wireless' | tail -200 || true
        echo "--- WPA supplicant log ---"
        [ ! -s "$wpa_log" ] || cat "$wpa_log"
    } > "$diag" 2>&1
}

save_to_loader_p3() {
    p3=
    if command -v blkid >/dev/null 2>&1; then
        p3=$(blkid -U 6234-C863 2>/dev/null)
        [ -n "$p3" ] || p3=$(blkid -U 8765-4321 2>/dev/null)
    fi
    [ -b /dev/synoboot3 ] && p3=/dev/synoboot3
    [ -b "$p3" ] || {
        log 'Could not locate loader P3 by UUID (6234-C863 or 8765-4321); diagnostics remain in volatile runtime.'
        return 1
    }

    mounted_path=$(awk -v d="$p3" '$1 == d {print $2; exit}' /proc/mounts 2>/dev/null)
    if [ -z "$mounted_path" ] && command -v readlink >/dev/null 2>&1; then
        p3_real=$(readlink -f "$p3" 2>/dev/null)
        [ -z "$p3_real" ] || mounted_path=$(awk -v d="$p3_real" '$1 == d {print $2; exit}' /proc/mounts 2>/dev/null)
    fi
    if [ -n "$mounted_path" ]; then
        mountpoint=$mounted_path
        mounted=2
    else
        mkdir "$mountpoint" || return 1
        mount -t vfat -o rw "$p3" "$mountpoint" >/dev/null 2>&1 || {
            log "Could not mount loader P3 ($p3); diagnostics remain in volatile runtime."
            rmdir "$mountpoint" 2>/dev/null || true
            return 1
        }
        mounted=1
    fi
    dest="$mountpoint/wifi-diagnostics"
    mkdir -p "$dest" || return 1
    stamp=$(date '+%Y%m%d-%H%M%S' 2>/dev/null)
    [ -n "$stamp" ] || stamp="boot-$$"
    cp "$diag" "$dest/$stamp.txt" || return 1
    [ ! -s "$wpa_log" ] || cp "$wpa_log" "$dest/$stamp-wpa.log" || return 1
    sync
    log "Wi-Fi diagnostics saved to loader P3: /wifi-diagnostics/$stamp.txt"
}

capture_and_save() {
    capture_diagnostics
    save_to_loader_p3 || true
}

count=0
while [ "$count" -lt 150 ]; do
    for path in /sys/class/net/*/phy80211; do
        [ -e "$path" ] || continue
        iface=${path%/phy80211}
        iface=${iface##*/}
        case "$iface" in p2p*) continue ;; esac

        # Never take over an interface already managed by another supplicant.
        if [ -S "/var/run/wpa_supplicant/$iface" ] || [ -s /run/mshell-wifi.pid ]; then
            log 'An existing WPA supplicant appears to own the wireless interface; skipping.'
            capture_and_save
            exit 0
        fi
        if ! ip link set "$iface" up; then
            log "Could not bring wireless interface $iface up."
            capture_and_save
            exit 1
        fi
        if ! "$runtime/lib/ld-musl-x86_64.so.1" --library-path "$runtime/lib" "$wpa" -B -D nl80211 -i "$iface" -c "$CONFIG" -P /run/mshell-wifi.pid -f "$wpa_log" >/dev/null 2>&1; then
            log 'Wireless authentication service failed to start.'
            capture_and_save
            exit 1
        fi
        started=1
        log "Wireless authentication service started on $iface; waiting up to 300 seconds for DSM networking."

        # Keep the process alive long enough to capture association, DHCP and
        # firmware errors, then copy a credential-free snapshot to loader P3.
        elapsed=0
        while [ "$elapsed" -lt 300 ]; do
            if ip -4 addr show dev "$iface" 2>/dev/null | awk '$1 == "inet" && $2 !~ /^169\.254\./ {found=1} END {exit !found}'; then
                sleep 15
                break
            fi
            sleep 5
            elapsed=$((elapsed + 5))
        done
        capture_and_save
        exit 0
    done
    sleep 2
    count=$((count + 1))
done

log 'No wireless interface appeared within 300 seconds.'
capture_and_save
exit 1
