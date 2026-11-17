#!/bin/sh
set +x
umask 077

CONFIG=/addons/mshell-wifi.conf
TOOLS=/exts/wifi-tools/wifi-tools.tgz
HAS_CONFIG=0
[ ! -s "$CONFIG" ] || HAS_CONFIG=1
mkdir /run/mshell-wifi.lock 2>/dev/null || exit 0

runtime=/run/mshell-wifi.$$
mountpoint=/run/mshell-wifi-p3.$$
mounted=0
mkdir "$runtime" || { rmdir /run/mshell-wifi.lock 2>/dev/null; exit 1; }
stamp=$(date '+%Y%m%d-%H%M%S' 2>/dev/null)
[ -n "$stamp" ] || stamp="boot-$$"

cleanup() {
    [ "$mounted" -ne 1 ] || umount "$mountpoint" >/dev/null 2>&1 || true
    [ "$mounted" -ne 1 ] || rmdir "$mountpoint" 2>/dev/null || true
    rmdir /run/mshell-wifi.lock 2>/dev/null || true
}
trap cleanup EXIT HUP INT TERM

iface=
started=0
wpa_log="$runtime/wpa_supplicant.log"
wpa=
tools_error=

log() {
    logger -t mshell-wifi "$1" 2>/dev/null || true
}

redact() {
    sed -E 's/((psk|PSK|password|Password|PASSWORD|passwd|Passphrase|passphrase)[[:space:]]*[:=][[:space:]]*)("[^"]*"|[^[:space:]]+)/\1[REDACTED]/g'
}

capture_diagnostics() {
    stage=$1
    snapshot="$runtime/$stage"
    mkdir -p "$snapshot/lrc"
    {
        echo "Capture time: $(date 2>/dev/null || echo unknown)"
        echo "Capture stage: $stage"
        echo "Wi-Fi config present: $HAS_CONFIG (contents intentionally excluded)"
        echo "Supplicant started: $started"
        echo "Wi-Fi interface: ${iface:-not-found}"
        echo "Tool extraction status: ${tools_error:-ok/not-needed}"
        if [ -n "$iface" ]; then
            echo "--- interface sysfs ---"
            for f in address operstate carrier; do
                if [ -r "/sys/class/net/$iface/$f" ]; then
                    printf '%s=' "$f"
                    cat "/sys/class/net/$iface/$f" 2>/dev/null
                fi
            done
        fi
        echo "--- all interface addresses ---"
        ip addr 2>&1 || ifconfig -a 2>&1 || true
        echo "--- routes ---"
        ip route 2>&1 || route -n 2>&1 || true
        echo "--- wireless modules ---"
        lsmod 2>&1 | grep -E '(^| )(wl|cfg80211|brcmfmac|brcmutil|ccm|gcm|cmac|r8152|usbnet|mii)( |$)' || true
        echo "--- processes ---"
        ps 2>&1 | grep -E 'wpa|dhcp|udhc|wifi|rcExit|install\.sh' | grep -v grep || true
        echo "--- mounts ---"
        mount 2>&1
        echo "--- relevant system log lines ---"
        for logfile in /var/log/messages /var/log/syslog; do
            [ ! -r "$logfile" ] || grep -iE 'wifi|wlan|wpa|wireless|cfg80211|brcm|firmware|dhcp|udhcpc|169\.254' "$logfile" 2>/dev/null | redact >> "$snapshot/system-wifi.log"
        done
    } > "$snapshot/summary.txt" 2>&1

    dmesg > "$snapshot/dmesg.txt" 2>&1 || true
    [ ! -s "$wpa_log" ] || redact < "$wpa_log" > "$snapshot/wpa_supplicant.log"

    if [ -d /var/log/lrc ]; then
        (cd /var/log/lrc && find . -type f -size -16384k -print) 2>/dev/null |
        while IFS= read -r rel; do
            [ -n "$rel" ] || continue
            out="$snapshot/lrc/${rel#./}"
            mkdir -p "${out%/*}"
            redact < "/var/log/lrc/${rel#./}" > "$out" 2>/dev/null || true
        done
        find /var/log/lrc -type f -size +16383k -print 2>/dev/null > "$snapshot/lrc-skipped-large-files.txt"
    else
        echo "/var/log/lrc not present at capture time" > "$snapshot/lrc-not-present.txt"
    fi
}

save_to_loader_p3() {
    stage=$1
    p3=
    if command -v blkid >/dev/null 2>&1; then
        p3=$(blkid -U 6234-C863 2>/dev/null)
        [ -n "$p3" ] || p3=$(blkid -U 8765-4321 2>/dev/null)
    fi
    [ -b /dev/synoboot3 ] && p3=/dev/synoboot3
    [ -b "$p3" ] || {
        log 'Could not locate loader P3 by UUID 6234-C863 or 8765-4321.'
        return 1
    }

    mounted_path=$(awk -v d="$p3" '$1 == d {print $2; exit}' /proc/mounts 2>/dev/null)
    if [ -z "$mounted_path" ] && command -v readlink >/dev/null 2>&1; then
        p3_real=$(readlink -f "$p3" 2>/dev/null)
        [ -z "$p3_real" ] || mounted_path=$(awk -v d="$p3_real" '$1 == d {print $2; exit}' /proc/mounts 2>/dev/null)
    fi
    if [ -n "$mounted_path" ]; then
        dest_root=$mounted_path
    else
        mkdir "$mountpoint" || return 1
        mount -t vfat -o rw "$p3" "$mountpoint" >/dev/null 2>&1 || {
            log "Could not mount loader P3 ($p3)."
            rmdir "$mountpoint" 2>/dev/null || true
            return 1
        }
        mounted=1
        dest_root=$mountpoint
    fi

    dest="$dest_root/wifi-diagnostics/$stamp"
    mkdir -p "$dest/$stage" || return 1
    cp -R "$runtime/$stage/." "$dest/$stage/" || return 1
    sync
    log "Junior diagnostics saved to loader P3: /wifi-diagnostics/$stamp/$stage/"
    if [ "$mounted" -eq 1 ]; then
        umount "$mountpoint" >/dev/null 2>&1 || return 1
        rmdir "$mountpoint" 2>/dev/null || true
        mounted=0
    fi
}

capture_and_save() {
    capture_diagnostics "$1"
    save_to_loader_p3 "$1" || true
}

# Save a pre-attempt snapshot immediately so a later failure cannot erase the
# only evidence from this boot. A second snapshot records the final state.
capture_and_save early

if [ "$HAS_CONFIG" -eq 0 ]; then
    log 'No Wi-Fi configuration found; saved boot diagnostics without starting supplicant.'
    exit 0
fi

if [ ! -s "$TOOLS" ] || ! tar -xzf "$TOOLS" -C "$runtime"; then
    tools_error='wifi-tools archive missing or extraction failed'
    log "$tools_error"
    capture_and_save final
    exit 1
fi
wpa="$runtime/bin/wpa_supplicant"

count=0
while [ "$count" -lt 150 ]; do
    for path in /sys/class/net/*/phy80211; do
        [ -e "$path" ] || continue
        iface=${path%/phy80211}
        iface=${iface##*/}
        case "$iface" in p2p*) continue ;; esac

        if [ -S "/var/run/wpa_supplicant/$iface" ] || [ -s /run/mshell-wifi.pid ]; then
            log 'An existing WPA supplicant appears to own the wireless interface; skipping.'
            capture_and_save final
            exit 0
        fi
        if ! ip link set "$iface" up; then
            log "Could not bring wireless interface $iface up."
            capture_and_save final
            exit 1
        fi
        if ! "$runtime/lib/ld-musl-x86_64.so.1" --library-path "$runtime/lib" "$wpa" -B -D nl80211 -i "$iface" -c "$CONFIG" -P /run/mshell-wifi.pid -f "$wpa_log" >/dev/null 2>&1; then
            log 'Wireless authentication service failed to start.'
            capture_and_save final
            exit 1
        fi
        started=1
        log "Wireless authentication service started on $iface; waiting up to 300 seconds for a non-link-local IPv4 address."

        elapsed=0
        while [ "$elapsed" -lt 300 ]; do
            if ip -4 addr show dev "$iface" 2>/dev/null | awk '$1 == "inet" && $2 !~ /^169\.254\./ {found=1} END {exit !found}'; then
                sleep 15
                break
            fi
            sleep 5
            elapsed=$((elapsed + 5))
        done
        capture_and_save final
        exit 0
    done
    sleep 2
    count=$((count + 1))
done

log 'No wireless interface appeared within 300 seconds.'
capture_and_save final
exit 1
