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
state=not-started
dhcp_status=not-started
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
        echo "WPA state: $state"
        echo "DHCP status: $dhcp_status"
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

find_uuid_device() {
    wanted_uuid=$1
    dev=
    if command -v blkid >/dev/null 2>&1; then
        dev=$(blkid -U "$wanted_uuid" 2>/dev/null)
        [ ! -b "$dev" ] && dev=$(blkid 2>/dev/null | grep -i "UUID=\"$wanted_uuid\"" | head -1 | cut -d: -f1)
    fi
    [ -b "$dev" ] && { echo "$dev"; return 0; }
    return 1
}

find_label_device() {
    wanted_label=$1
    dev=
    if command -v blkid >/dev/null 2>&1; then
        dev=$(blkid -L "$wanted_label" 2>/dev/null)
        [ ! -b "$dev" ] && dev=$(blkid 2>/dev/null | grep -i "LABEL=\"$wanted_label\"" | head -1 | cut -d: -f1)
    fi
    [ -b "$dev" ] && { echo "$dev"; return 0; }
    return 1
}

save_to_device() {
    dev=$1
    target_name=$2
    stage=$3
    mountpoint="/run/mshell-wifi-$target_name.$$"
    mounted=0
    result=0
    [ -b "$dev" ] || return 1

    mounted_path=$(awk -v d="$dev" '$1 == d {print $2; exit}' /proc/mounts 2>/dev/null)
    if [ -z "$mounted_path" ] && command -v readlink >/dev/null 2>&1; then
        dev_real=$(readlink -f "$dev" 2>/dev/null)
        [ -z "$dev_real" ] || mounted_path=$(awk -v d="$dev_real" '$1 == d {print $2; exit}' /proc/mounts 2>/dev/null)
    fi
    if [ -n "$mounted_path" ]; then
        dest_root=$mounted_path
    else
        mkdir "$mountpoint" || return 1
        mount -t vfat -o rw "$dev" "$mountpoint" >/dev/null 2>&1 || {
            log "Could not mount $target_name storage ($dev)."
            rmdir "$mountpoint" 2>/dev/null || true
            return 1
        }
        mounted=1
        dest_root=$mountpoint
    fi

    dest="$dest_root/wifi-diagnostics/$stamp/$stage"
    mkdir -p "$dest" || result=1
    [ "$result" -ne 0 ] || cp -R "$runtime/$stage/." "$dest/" || result=1
    [ "$result" -ne 0 ] || sync
    if [ "$mounted" -eq 1 ]; then
        umount "$mountpoint" >/dev/null 2>&1 || result=1
        rmdir "$mountpoint" 2>/dev/null || true
        mounted=0
    fi
    if [ "$result" -eq 0 ]; then
        log "Junior diagnostics saved to $target_name: /wifi-diagnostics/$stamp/$stage/"
    else
        log "Failed writing Junior diagnostics to $target_name ($dev)."
    fi
    return "$result"
}

save_to_loader_p3() {
    stage=$1
    p3=$(find_uuid_device 6234-C863) || p3=$(find_uuid_device 8765-4321) || true
    [ -b /dev/synoboot3 ] && p3=/dev/synoboot3
    [ -b "$p3" ] || {
        log 'Loader P3 not found by UUID 6234-C863/8765-4321 or /dev/synoboot3.'
        return 1
    }
    save_to_device "$p3" loader-p3 "$stage"
}

save_to_sd_card() {
    stage=$1
    sd=$(find_label_device WIFILOG) || true
    [ -b "$sd" ] || {
        log 'Secondary SD log volume with label WIFILOG not found.'
        return 1
    }
    save_to_device "$sd" sd-wifilog "$stage"
}

capture_and_save() {
    stage=$1
    capture_diagnostics "$stage"
    p3_saved=0
    sd_saved=0
    save_to_loader_p3 "$stage" && p3_saved=1
    save_to_sd_card "$stage" && sd_saved=1
    if [ "$p3_saved" -eq 0 ] && [ "$sd_saved" -eq 0 ]; then
        log "No persistent destination accepted the $stage diagnostic snapshot."
    fi
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
wpa_cli="$runtime/bin/wpa_cli"
loader="$runtime/lib/ld-musl-x86_64.so.1"
ctrl="$runtime/ctrl"
runtime_config="$runtime/wpa.conf"
{ printf 'ctrl_interface=%s\n' "$ctrl"; cat "$CONFIG"; } > "$runtime_config" || exit 1

count=0
while [ "$count" -lt 150 ]; do
    for path in /sys/class/net/*/phy80211; do
        [ -e "$path" ] || continue
        iface=${path%/phy80211}
        iface=${iface##*/}
        case "$iface" in p2p*) continue ;; esac

        existing_pid=$(cat /run/mshell-wifi.pid 2>/dev/null)
        case "$existing_pid" in *[!0-9]*|'') existing_pid= ;; esac
        if [ -S "/var/run/wpa_supplicant/$iface" ] || { [ -n "$existing_pid" ] && kill -0 "$existing_pid" 2>/dev/null; }; then
            log 'An existing WPA supplicant appears to own the wireless interface; skipping.'
            capture_and_save final
            exit 0
        fi
        if ! ip link set "$iface" up; then
            log "Could not bring wireless interface $iface up."
            capture_and_save final
            exit 1
        fi
        "$loader" --library-path "$runtime/lib" "$wpa" -D nl80211 -i "$iface" -c "$runtime_config" > "$wpa_log" 2>&1 </dev/null &
        wpa_pid=$!
        printf '%s\n' "$wpa_pid" > /run/mshell-wifi.pid
        sleep 2
        if ! kill -0 "$wpa_pid" 2>/dev/null; then
            log 'Wireless authentication service failed to start.'
            rm /run/mshell-wifi.pid 2>/dev/null || true
            capture_and_save final
            exit 1
        fi
        started=1
        log "Wireless authentication service started on $iface; waiting up to 300 seconds for a non-link-local IPv4 address."

        elapsed=0
        connected=0
        dhcp_attempted=0
        while [ "$elapsed" -lt 300 ]; do
            state=$("$loader" --library-path "$runtime/lib" "$wpa_cli" -p "$ctrl" -i "$iface" status 2>/dev/null | sed -n 's/^wpa_state=//p')
            if [ "$state" = COMPLETED ] && ip -4 addr show dev "$iface" 2>/dev/null | awk '$1 == "inet" && $2 !~ /^169\.254\./ {found=1} END {exit !found}'; then
                connected=1
                sleep 15
                break
            fi
            if [ "$state" = COMPLETED ] && [ "$dhcp_attempted" -eq 0 ]; then
                dhcp_attempted=1
                # Allow the existing DSM manager a grace period. Never start a
                # competing DHCP client or change routes/DNS from this worker.
                sleep 10
                if ps 2>/dev/null | grep -E "[u]dhcpc .*\-i[ =]*${iface}([[:space:]]|$)|[d]hcpcd .*${iface}([[:space:]]|$)" >/dev/null; then
                    dhcp_status=existing-client
                else
                    dhcp_status=no-client
                    log "No DHCP client detected on $iface; leaving network configuration to DSM."
                fi
            fi
            if ! kill -0 "$wpa_pid" 2>/dev/null; then
                log 'Wireless authentication service exited unexpectedly.'
                break
            fi
            sleep 5
            elapsed=$((elapsed + 5))
        done
        capture_and_save final
        if [ "$connected" -eq 1 ]; then
            log "Wireless authentication and IPv4 address confirmed on $iface."
            exit 0
        fi
        log "Wi-Fi authentication or IPv4 assignment timed out on $iface (state=${state:-unknown})."
        exit 1
    done
    sleep 2
    count=$((count + 1))
done

log 'No wireless interface appeared within 300 seconds.'
capture_and_save final
exit 1
