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

# /linuxrc.syno exists in the DSM junior root and is absent after DSM takes
# over the root filesystem. Keep this display helper scoped to junior mode.
[ -x /linuxrc.syno ] || exit 0

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
    "$ADDON_DIR/kms-display" "$STATUS_FILE" >>/var/log/junior-realtime-helper.log 2>&1 &
    echo "$!" >/tmp/junior-realtime-helper-kms.pid
fi

addresses() {
    primary=$(ip route show default 2>/dev/null |
        awk 'NR == 1 {for (i = 1; i < NF; i++) if ($i == "dev") {print $(i + 1); exit}}')
    ip -o -4 addr show scope global 2>/dev/null |
        awk -v primary="$primary" '{
            name=$2
            if (name == "lo" || name ~ /^(docker|veth|br-|virbr|tun|tap)/) next
            split($4, a, "/")
            if (!a[1]) next
            if (name == primary) print name, a[1]
            else other[++n]=name " " a[1]
        } END {for (i=1; i<=n; i++) print other[i]}'
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

render_status() {
    [ -c "$CONSOLE" ] || return 1
    {
        printf '\033[s\033[H'
        row=0
        while [ "$row" -lt 24 ]; do
            printf '\033[2K\r\n'
            row=$((row + 1))
        done
        printf '\033[H'
        printf '\033[2KJUNIOR REALTIME HELPER\r\n'
        printf '\033[2K\033[38;5;218m##### TCRP MSHELL LOADER #####\033[0m\r\n'
        printf '\033[2K\r\n'
        printf '\033[2KMODEL : %s  DSM %s-%s\r\n' "$model" "$product" "$build"
        printf '\033[2KSERIAL %s\r\n' "$serial"
        printf '\033[2KMAC %s\r\n' "$mac"
        printf '\033[2KCPU %s\r\n' "$cpu"
        printf '\033[2KTHREADS %s\r\n' "$threads"
        printf '\033[2KPLATFORM %s\r\n' "$platform"
        printf '\033[2KDMI %s\r\n' "$dmi"
        printf '\033[2KBOOT %s  HBA %s  NIC %s  GPU %s\r\n' \
            "$boot" "$hba" "$pci_nics" "$gpu_count"
        printf '\033[2KNETWORK INTERFACES\r\n'
        shown=0
        printf '%s\n' "$(nic_list)" | while IFS= read -r nic; do
            [ -n "$nic" ] || continue
            [ "$shown" -lt 2 ] || break
            printf '\033[2K%s\r\n' "$nic"
            shown=$((shown + 1))
        done
        printf '\033[2KCMDLINE : %s\r\n' "$(cat /proc/cmdline 2>/dev/null)"
        printf '\033[2KGRAPHICS\r\n'
        shown=0
        printf '%s\n' "$(gpu_list)" | while IFS= read -r gpu; do
            [ -n "$gpu" ] || continue
            [ "$shown" -lt 2 ] || break
            printf '\033[2K%s\r\n' "$gpu"
            shown=$((shown + 1))
        done
        printf '\033[2KJUNIOR REALTIME HELPER\r\n'
        printf '\033[2KCURRENT IP %s  GATEWAY PING %s\r\n' "$ip" "$ping"
        printf '\033[2KDISPLAY REFRESH : %s (2s interval)\r\n' "$refresh"
        printf '\033[2KDSM TCP/5000 %s\r\n' "$port"
        printf '\033[2KRECOGNIZED DISKS %s  SATA/OTHER %s  NVME %s\r\n' \
            "$count" "$sata_count" "$nvme_count"
        printf '\033[2KDEVICE  SIZE  MODEL\r\n'
        shown=0
        printf '%s\n' "$disks" | while IFS= read -r disk; do
            [ -n "$disk" ] || continue
            [ "$shown" -lt 4 ] || break
            printf '\033[2K%s\r\n' "$disk"
            shown=$((shown + 1))
        done
        printf '\033[u'
    } >"$CONSOLE"
}

previous=''
while :; do
    [ -x /linuxrc.syno ] || exit 0
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
    platform=$(version_value unique); [ -n "$platform" ] || platform=UNKNOWN
    cpu=$(awk -F: '/^model name/ {sub(/^[ \t]+/, "", $2); print $2; exit}' /proc/cpuinfo |
        tr -cd '[:alnum:] ._:/()-')
    [ -n "$cpu" ] || cpu=UNKNOWN
    threads=$(grep -c '^processor[[:space:]]*:' /proc/cpuinfo 2>/dev/null)
    [ -n "$threads" ] || threads=0
    dmi_vendor=$(cat /sys/class/dmi/id/sys_vendor 2>/dev/null)
    dmi_product=$(cat /sys/class/dmi/id/product_name 2>/dev/null)
    dmi_board=$(cat /sys/class/dmi/id/board_name 2>/dev/null)
    dmi=$(printf '%s %s %s' "$dmi_vendor" "$dmi_product" "$dmi_board" |
        tr -cd '[:alnum:] ._:/()-')
    [ -n "$dmi" ] || dmi=UNAVAILABLE
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
