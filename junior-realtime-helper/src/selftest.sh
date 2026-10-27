#!/bin/sh
# Copyright (C) 2026 PeterSuh-Q3. See repository LICENSE.
# Read-only junior status monitor. Never mounts, formats or writes a disk.
export PATH=/usr/syno/bin:/usr/syno/sbin:/usr/bin:/usr/sbin:/bin:/sbin
trap '' HUP
ADDON_DIR=${0%/*}
STATUS_FILE=/tmp/junior-realtime-helper.status
LOCK_DIR=/var/run/junior-realtime-helper
CONSOLE=/dev/tty1
active_console=$(cat /sys/devices/virtual/tty/tty0/active 2>/dev/null)
case "$active_console" in tty[0-9]*) [ -c "/dev/$active_console" ] && CONSOLE="/dev/$active_console" ;; esac

is_junior_mode() {
    [ -x /linuxrc.syno ]
}

has_drm_card() {
    for card in /dev/dri/card[0-9]*; do
        [ -c "$card" ] && return 0
    done
    return 1
}

runtime_mode() {
    if is_junior_mode; then
        printf 'JUNIOR\n'
    elif has_drm_card; then
        printf 'DSM\n'
    fi
}

# DSM rc.d starts the monitor on DSM 7 only. Junior starts through on_jrExit.
[ -n "$(runtime_mode)" ] || exit 0

# The on_jrExit hook can be called more than once. mkdir is atomic, so only
# one monitor owns the status file and DRM helper.
if ! mkdir "$LOCK_DIR" 2>/dev/null; then
    owner=$(cat "$LOCK_DIR/pid" 2>/dev/null)
    if [ -n "$owner" ] && kill -0 "$owner" 2>/dev/null; then
        exit 0
    fi
    rm -f "$LOCK_DIR/pid" 2>/dev/null
    rmdir "$LOCK_DIR" 2>/dev/null || exit 0
    mkdir "$LOCK_DIR" 2>/dev/null || exit 0
fi
printf '%s\n' "$$" >"$LOCK_DIR/pid"

cleanup() {
    trap - 0 INT TERM
    owner=$(cat "$LOCK_DIR/pid" 2>/dev/null)
    if [ "$owner" = "$$" ]; then
        kms_pid=$(cat /tmp/junior-realtime-helper-kms.pid 2>/dev/null)
        if [ -n "$kms_pid" ]; then
            kill "$kms_pid" 2>/dev/null
            wait "$kms_pid" 2>/dev/null
        fi
        [ "$(cat /tmp/junior-realtime-helper-kms.pid 2>/dev/null)" = "$kms_pid" ] &&
            rm -f /tmp/junior-realtime-helper-kms.pid
        [ "$(cat /tmp/junior-realtime-helper.pid 2>/dev/null)" = "$$" ] &&
            rm -f /tmp/junior-realtime-helper.pid
        rm -f "$LOCK_DIR/pid"
        rmdir "$LOCK_DIR" 2>/dev/null
    fi
}
trap cleanup 0
trap 'exit 0' INT TERM

if [ -x "$ADDON_DIR/kms-display" ] &&
   { [ ! -r /tmp/junior-realtime-helper-kms.pid ] ||
     ! kill -0 "$(cat /tmp/junior-realtime-helper-kms.pid 2>/dev/null)" 2>/dev/null; }; then
    kms_driver=
    for pci_device in /sys/bus/pci/devices/*; do
        [ -r "$pci_device/vendor" ] && [ -r "$pci_device/device" ] || continue
        [ "$(cat "$pci_device/vendor" 2>/dev/null)" = 0x1234 ] || continue
        [ "$(cat "$pci_device/device" 2>/dev/null)" = 0x1111 ] || continue
        kms_driver=bochs-drm
        break
    done
    if [ -n "$kms_driver" ]; then
        "$ADDON_DIR/kms-display" "$STATUS_FILE" "$kms_driver" >>/var/log/junior-realtime-helper.log 2>&1 &
    else
        "$ADDON_DIR/kms-display" "$STATUS_FILE" >>/var/log/junior-realtime-helper.log 2>&1 &
    fi
    echo "$!" >/tmp/junior-realtime-helper-kms.pid
fi

addresses() {
    primary=$(ip route show default 2>/dev/null |
        awk 'NR == 1 {for (i = 1; i < NF; i++) if ($i == "dev") {print $(i + 1); exit}}')
    [ -n "$primary" ] || return 0
    ip -o -4 addr show dev "$primary" scope global 2>/dev/null |
        awk 'NR == 1 {split($4, a, "/"); if (a[1]) print $2, a[1]; exit}'
}

link_up() {
    nic=$1
    [ -n "$nic" ] || return 1
    if [ -r "/sys/class/net/$nic/carrier" ]; then
        [ "$(cat "/sys/class/net/$nic/carrier" 2>/dev/null)" = 1 ]
        return $?
    fi
    [ "$(cat "/sys/class/net/$nic/operstate" 2>/dev/null)" = up ]
}

gateway_for() {
    ip route show default dev "$1" 2>/dev/null |
        awk 'NR == 1 {for (i = 1; i < NF; i++) if ($i == "via") {print $(i + 1); exit}}'
}

disk_list() {
    loader_p3_uuid=
    loader_devno=
    if [ -b /dev/synoboot3 ] && [ -x /sbin/blkid ]; then
        loader_p3_uuid=$(/sbin/blkid -s UUID -o value /dev/synoboot3 2>/dev/null)
        set -- $(ls -l /dev/synoboot3 2>/dev/null)
        if [ -n "$loader_p3_uuid" ] && [ -n "${5:-}" ] && [ -n "${6:-}" ]; then
            loader_devno="${5%,}:$6"
        else
            loader_p3_uuid=
        fi
    fi
    for path in /sys/block/sd* /sys/block/sata* /sys/block/nvme*n* /sys/block/vd*; do
        [ -e "$path/size" ] || continue
        name=${path##*/}
        case "$name" in *[!a-zA-Z0-9]*) continue ;; esac
        case "$name" in sd*) p3="$path/${name}3" ;; *) p3="$path/${name}p3" ;; esac
        if [ -n "$loader_p3_uuid" ] && [ -n "$loader_devno" ] &&
           [ -r "$p3/dev" ] && [ "$(cat "$p3/dev" 2>/dev/null)" = "$loader_devno" ]; then
            continue
        fi
        sectors=$(cat "$path/size" 2>/dev/null) || continue
        [ "$sectors" -gt 0 ] 2>/dev/null || continue
        model=$(cat "$path/device/model" 2>/dev/null | tr -cd '[:alnum:] ._-')
        mb=$((sectors / 2048))
        printf '%s %sMB %s\n' "$name" "$mb" "$model"
    done
}

cmdline_value() {
    awk -v key="$1" '{
        for (i = 1; i <= NF; i++)
            if (index($i, key "=") == 1) {
                sub("^[^=]*=", "", $i)
                print $i
                exit
            }
    }' /proc/cmdline 2>/dev/null
}

version_value() {
    file=/etc.defaults/VERSION
    [ -r "$file" ] || file=/etc/VERSION
    awk -F= -v key="$1" '$1 == key {gsub(/"/, "", $2); print $2; exit}' "$file" 2>/dev/null
}

synoinfo_value() {
    awk -F= -v key="$1" '$1 == key {gsub(/^[[:space:]]+|[[:space:]]+$/, "", $2); sub(/^"/, "", $2); sub(/"$/, "", $2); print $2; exit}' \
        /etc.defaults/synoinfo.conf 2>/dev/null
}

dmi_field() {
    value=$(cat "/sys/class/dmi/id/$1" 2>/dev/null | tr -cd '[:alnum:] ._:/()-')
    if [ -z "$value" ] && command -v dmidecode >/dev/null 2>&1; then
        value=$(dmidecode -s "$2" 2>/dev/null | sed -n '1p' | tr -cd '[:alnum:] ._:/()-')
    fi
    printf '%s\n' "$value"
}

dmi_summary() {
    mode=$1
    if [ "$mode" = DSM ] && [ -r /usr/mshell/DMI ]; then
        value=$(awk 'NF {if (out) out=out " "; out=out $0} END {print out}' \
            /usr/mshell/DMI 2>/dev/null | tr -cd '[:alnum:] ._:/()-' |
            sed 's/  */ /g; s/^ //; s/ $//')
        if [ -n "$value" ]; then
            printf '%s\n' "$value"
            return
        fi
    fi

    vendor=$(dmi_field sys_vendor system-manufacturer)
    product=$(dmi_field product_name system-product-name)
    board=$(dmi_field board_name baseboard-product-name)
    if [ -n "$vendor$product$board" ]; then
        summary=$(printf '%s %s %s' "$vendor" "$product" "$board" | sed 's/  */ /g; s/^ //; s/ $//')
        if [ -z "$board" ]; then
            profile_platform=$(synoinfo_value platform_name)
            profile_model=$(synoinfo_value upnpmodelname)
            summary="$summary; board DMI unavailable"
            if [ -n "$profile_platform$profile_model" ]; then
                summary="$summary (DSM profile $profile_platform/$profile_model)"
            fi
        fi
        printf '%s\n' "$summary"
        return
    fi

    profile_platform=$(synoinfo_value platform_name)
    profile_model=$(synoinfo_value upnpmodelname)
    if [ -n "$profile_platform$profile_model" ]; then
        printf 'SMBIOS unavailable; DSM profile %s/%s (not board DMI)\n' \
            "${profile_platform:-UNKNOWN}" "${profile_model:-UNKNOWN}"
    else
        printf 'UNAVAILABLE\n'
    fi
}

addon_value() {
    file="$1"
    label=$2
    value=$(awk -v label="$label" '
        NR == 1 {
            sub(/\r$/, "")
            sub("^[[:space:]]*" label "[[:space:]]*:[[:space:]]*", "")
            print
            exit
        }
    ' "$file" 2>/dev/null)
    [ -n "$value" ] || value=UNKNOWN
    printf '%s\n' "$value"
}

pci_counts() {
    hba=0
    pci_nics=0
    gpu=0
    for path in /sys/bus/pci/devices/*; do
        [ -r "$path/class" ] || continue
        class=$(cat "$path/class" 2>/dev/null)
        case "$class" in
            0x0104*|0x0107*) hba=$((hba + 1)) ;;
            0x0200*) pci_nics=$((pci_nics + 1)) ;;
            0x03*) gpu=$((gpu + 1)) ;;
        esac
    done
    printf '%s %s %s\n' "$hba" "$pci_nics" "$gpu"
}

nic_list() {
    shown=0
    for path in /sys/class/net/*; do
        [ -r "$path/address" ] || continue
        name=${path##*/}
        [ "$name" = lo ] && continue
        [ "$shown" -lt 8 ] || break
        addr=$(ip -o -4 addr show dev "$name" 2>/dev/null | awk 'NR == 1 {print $4}')
        [ -n "$addr" ] || addr=NO-IP
        link=$(readlink "$path/device" 2>/dev/null)
        busid=${link##*/}
        [ -n "$busid" ] || busid=USB-or-virtual
        vendor=$(cat "$path/device/vendor" 2>/dev/null | sed 's/^0x//')
        device=$(cat "$path/device/device" 2>/dev/null | sed 's/^0x//')
        [ -n "$vendor" ] || vendor=----
        [ -n "$device" ] || device=----
        link=$(readlink "$path/device/driver" 2>/dev/null)
        driver=${link##*/}
        [ -n "$driver" ] || driver=unknown
        printf '%s %s via %s %s:%s (%s)\n' "$name" "$addr" "$busid" \
            "$vendor" "$device" "$driver" | tr -cd '[:alnum:] ._:/()\n-'
        shown=$((shown + 1))
    done
}

gpu_list() {
    shown=0
    for path in /sys/bus/pci/devices/*; do
        [ -r "$path/class" ] || continue
        class=$(cat "$path/class" 2>/dev/null)
        case "$class" in 0x03*) ;; *) continue ;; esac
        [ "$shown" -lt 4 ] || break
        vendor=$(cat "$path/vendor" 2>/dev/null | sed 's/^0x//')
        device=$(cat "$path/device" 2>/dev/null | sed 's/^0x//')
        link=$(readlink "$path/driver" 2>/dev/null)
        driver=${link##*/}
        [ -n "$driver" ] || driver=unbound
        printf '%s [%s:%s] (%s)\n' "${path##*/}" "$vendor" "$device" \
            "$driver" | tr -cd '[:alnum:] ._:/()\n-'
        shown=$((shown + 1))
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

ping_status() {
    nic=$1
    target=$2
    [ -n "$nic" ] || { printf 'WAITING\n'; return; }
    link_up "$nic" || { printf 'NO REPLY (LINK DOWN)\n'; return; }
    [ -n "$target" ] || { printf 'NO ROUTE\n'; return; }
    for probe in /bin/ping /usr/bin/ping /sbin/ping; do
        [ -x "$probe" ] || continue
        output=$("$probe" -I "$nic" -c 1 -W 1 "$target" 2>&1)
        if [ "$?" -eq 0 ]; then
            rtt=$(printf '%s\n' "$output" | sed -n 's/.* time=\([0-9.][0-9.]*\) ms.*/\1/p' | head -n 1)
            [ -n "$rtt" ] && printf 'REPLY %s ms GW %s\n' "$rtt" "$target" || printf 'REPLY GW %s\n' "$target"
        else
            printf 'NO REPLY\n'
        fi
        return
    done
    printf 'UNAVAILABLE\n'
}

play_congratulations_once() {
    # The melody is a Junior success cue. DSM starts the same monitor silently.
    [ "$mode" = JUNIOR ] || return 0
    [ "$port" = READY ] || return 0
    case "$ping" in REPLY*) ;; *) return 0 ;; esac
    marker=/tmp/junior-realtime-helper.congratulations
    [ -e "$marker" ] && return 0
    beep=
    for probe in /exts/beep/beep /usr/bin/beep /bin/beep /tmpRoot/usr/bin/beep; do
        [ -x "$probe" ] || continue
        beep=$probe
        break
    done
    [ -n "$beep" ] || return 0
    mkdir "$marker" 2>/dev/null || return 0
    (
        # The beep addon keeps its binary and runtime library in /exts until
        # the late DSM event. Junior must use both directly from that folder.
        if [ "$beep" = /exts/beep/beep ]; then
            LD_LIBRARY_PATH="/exts/beep${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
            export LD_LIBRARY_PATH
        fi
        # Two refrain lines, with pitches and rests from the reference melody.
        "$beep" -f 494 -l 303 -D 11 -n \
            -f 554 -l 290 -D 18 -n \
            -f 622 -l 263 -D 57 -n \
            -f 659 -l 556 -D 51 -n \
            -f 494 -l 697 -D 268 -n \
            -f 659 -l 268 -D 15 -n \
            -f 622 -l 254 -D 28 -n \
            -f 659 -l 312 -D 20 -n \
            -f 740 -l 625 -D 7 -n \
            -f 554 -l 707 -D 272 -n \
            -f 554 -l 281 -D 16 -n \
            -f 622 -l 276 -D 21 -n \
            -f 659 -l 314 -D 25 -n \
            -f 831 -l 270 -D 16 -n \
            -f 740 -l 304 -D 21 -n \
            -f 740 -l 306 -D 21 -n \
            -f 659 -l 306 -D 28 -n \
            -f 659 -l 286 -D 13 -n \
            -f 622 -l 301 -D 13 -n \
            -f 554 -l 301 -D 7 -n \
            -f 622 -l 299 -D 20 -n \
            -f 494 -l 1057 -D 0 >>/var/log/junior-realtime-helper.log 2>&1
        result=$?
        if [ "$result" -eq 0 ]; then
            printf '%s congratulations melody played via %s\n' "$(date '+%H:%M:%S')" "$beep" \
                >>/var/log/junior-realtime-helper.log
        else
            printf '%s congratulations melody failed (%s) via %s\n' \
                "$(date '+%H:%M:%S')" "$result" "$beep" \
                >>/var/log/junior-realtime-helper.log
            rmdir "$marker" 2>/dev/null
        fi
    ) &
}

render_status() {
    [ -c "$CONSOLE" ] || return 1
    {
        printf '\033[2J\033[H'
        printf '\033[2K\033[38;5;218m##### TCRP MSHELL LOADER #####\033[0m\r\n'
        printf '\033[2K\r\n'
        printf '\033[2KMODEL : %s\r\n' "$model"
        printf '\033[2KSERIAL : %s\r\n' "$serial"
        printf '\033[2KMAC : %s\r\n' "$mac"
        printf '\033[2KBUILD : %s-%s\r\n' "$product" "$build"
        printf '\033[2KUPDATE : %s\r\n' "$update"
        printf '\033[2KLKM : %s\r\n' "$lkm_version"
        printf '\033[2Ktcrp-modules : %s\r\n' "$modules_version"
        printf '\033[2KModule Type : %s\r\n' "$module_type"
        printf '\033[2KLoader version : %s\r\n' "$loader_version"
        printf '\033[2KPLATFORM : %s\r\n' "$platform"
        shown=0
        printf '%s\n' "$(gpu_list)" | while IFS= read -r gpu; do
            [ -n "$gpu" ] || continue
            [ "$shown" -lt 2 ] || break
            printf '\033[2KGPU : %s\r\n' "$gpu"
            shown=$((shown + 1))
        done
        printf '\033[2KCPU : %s\r\n' "$cpu"
        printf '\033[2KTHREADS : %s\r\n' "$threads"
        printf '\033[2KDMI : %s\r\n' "$dmi"
        printf '\033[2KSAS/RAID HBAs Count : %s\r\n' "$hba"
        printf '\033[2KNICs Count : %s\r\n' "$pci_nics"
        printf '\033[2KGPU Count : %s\r\n' "$gpu_count"
        printf '\033[2KSAS/SATA Disks Count : %s\r\n' "$sata_count"
        printf '\033[2KNVMe Disks Count : %s\r\n' "$nvme_count"
        printf '\033[2KSystem is running in %s boot mode\r\n' "$boot"
        shown=0
        printf '%s\n' "$(nic_list)" | while IFS= read -r nic; do
            [ -n "$nic" ] || continue
            [ "$shown" -lt 2 ] || break
            printf '\033[2KNetwork : %s\r\n' "$nic"
            shown=$((shown + 1))
        done
        printf '\033[2KCMDLINE :\r\n'
        printf '\033[2K%s\r\n' "$(cat /proc/cmdline 2>/dev/null)"
        printf '\033[2KJUNIOR REALTIME HELPER\r\n'
        printf '\033[2KCurrent IP : %s\r\n' "$ip"
        printf '\033[2KGateway Ping : %s\r\n' "$ping"
        printf '\033[2KDSM TCP/5000 : %s\r\n' "$port"
        printf '\033[2KRecognized Disks : %s\r\n' "$count"
        printf '\033[2KDEVICE  SIZE  MODEL\r\n'
        shown=0
        printf '%s\n' "$disks" | while IFS= read -r disk; do
            [ -n "$disk" ] || continue
            [ "$shown" -lt 4 ] || break
            printf '\033[2K%s\r\n' "$disk"
            shown=$((shown + 1))
        done
        printf '\033[2KDISPLAY REFRESH : %s (2s interval)\r\n' "$refresh"
    } >"$CONSOLE"
}

previous=''
dmi=$(dmi_summary "$(runtime_mode)")
while :; do
    mode=$(runtime_mode)
    [ -n "$mode" ] || exit 0
    addresses=$(addresses)
    disks=$(disk_list)
    count=$(printf '%s\n' "$disks" | awk 'NF {n++} END {print n+0}')
    selected=$(printf '%s\n' "$addresses" | head -n 1)
    iface=
    ip=WAITING
    port=WAITING
    gateway=
    ping=WAITING
    if [ -n "$selected" ]; then
        set -- $selected
        iface=$1
        ip=$2
        gateway=$(gateway_for "$iface")
        if link_up "$iface"; then
            port='NOT READY'
            port_ready "$ip" && port=READY
            ping=$(ping_status "$iface" "$gateway")
        else
            port='NOT READY'
            ping='NO REPLY (LINK DOWN)'
        fi
    fi
    play_congratulations_once
    current=$(printf 'ip=%s interface=%s gateway=%s tcp5000=%s ping=%s kernel_disks=%s\n%s' \
        "$ip" "$iface" "$gateway" "$port" "$ping" "$count" "$disks")
    if [ "$current" != "$previous" ]; then
        printf '%s\n' "$current"
        previous=$current
    fi
    model=$(cmdline_value syno_hw_version); [ -n "$model" ] || model=UNKNOWN
    serial=$(cmdline_value sn); [ -n "$serial" ] || serial=N/A
    mac=$(cmdline_value mac1); [ -n "$mac" ] || mac=N/A
    product=$(version_value productversion); [ -n "$product" ] || product=DSM
    build=$(version_value buildnumber); [ -n "$build" ] || build=UNKNOWN
    update=$(version_value smallfixnumber); [ -n "$update" ] || update=UNKNOWN
    platform=$(version_value unique)
    [ -n "$platform" ] || platform=$(synoinfo_value platform_name)
    [ -n "$platform" ] || platform=UNKNOWN
    metadata_dir=/usr/mshell
    [ "$mode" = JUNIOR ] && metadata_dir=/addons
    lkm_version=$(addon_value "$metadata_dir/LKM_VERSION" LKM)
    modules_version=$(addon_value "$metadata_dir/MODULES_VERSION" tcrp-modules)
    module_type=$(addon_value "$metadata_dir/MODULE_TYPE" 'Module Type')
    loader_version=$(addon_value "$metadata_dir/VERSION" 'Loader version')
    cpu=$(awk -F: '/^model name/ {sub(/^[ \t]+/, "", $2); print $2; exit}' /proc/cpuinfo |
        tr -cd '[:alnum:] ._:/()-')
    [ -n "$cpu" ] || cpu=UNKNOWN
    threads=$(grep -c '^processor[[:space:]]*:' /proc/cpuinfo 2>/dev/null)
    [ -n "$threads" ] || threads=0
    set -- $(pci_counts)
    hba=${1:-0}; pci_nics=${2:-0}; gpu_count=${3:-0}
    refresh=$(date '+%H:%M:%S' 2>/dev/null)
    [ -n "$refresh" ] || refresh=UNKNOWN
    cmdline=$(cat /proc/cmdline 2>/dev/null | tr '\r\n' '  ')
    nvme_count=$(printf '%s\n' "$disks" | awk '$1 ~ /^nvme/ {n++} END {print n+0}')
    sata_count=$((count - nvme_count))
    boot=LEGACY
    case " $(cat /proc/cmdline 2>/dev/null) " in *" withefi "*) boot=UEFI ;; esac
    {
        printf 'IP=%s\nPING=%s\nPORT=%s\nDISK_COUNT=%s\nREFRESH=%s\nCMDLINE=%s\n' \
            "$ip" "$ping" "$port" "$count" "$refresh" "$cmdline"
        printf 'MODEL=%s\nSERIAL=%s\nMAC=%s\n' "$model" "$serial" "$mac"
        printf 'BUILD=%s-%s\nUPDATE=%s\nPLATFORM=%s\n' "$product" "$build" "$update" "$platform"
        printf 'LKM_VERSION=%s\nMODULES_VERSION=%s\nMODULE_TYPE=%s\nLOADER_VERSION=%s\n' \
            "$lkm_version" "$modules_version" "$module_type" "$loader_version"
        printf 'CPU=%s\nTHREADS=%s\nDMI=%s\n' "$cpu" "$threads" "$dmi"
        printf 'HBA_COUNT=%s\nPCI_NIC_COUNT=%s\nGPU_COUNT=%s\n' "$hba" "$pci_nics" "$gpu_count"
        printf 'SATA_COUNT=%s\nNVME_COUNT=%s\nBOOT=%s\n' "$sata_count" "$nvme_count" "$boot"
        printf '%s\n' "$(nic_list)" | while IFS= read -r row; do
            [ -n "$row" ] && printf 'NIC=%s\n' "$row"
        done
        printf '%s\n' "$(gpu_list)" | while IFS= read -r row; do
            [ -n "$row" ] && printf 'GPU=%s\n' "$row"
        done
        printf '%s\n' "$disks" | awk 'NF && n++ < 8 {print "DISK=" $0}'
    } >/tmp/junior-realtime-helper.status.new &&
        mv -f /tmp/junior-realtime-helper.status.new "$STATUS_FILE"
    render_status || printf 'junior-realtime-helper: cannot write %s\n' "$CONSOLE" >&2
    sleep 2
done
