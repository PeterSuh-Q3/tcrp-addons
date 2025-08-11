#!/usr/bin/env sh
# RR + mshell 완전통합 disks.sh (flock 대체 버전)

ROOT_PATH=""
GKV=$([ -x "/usr/syno/bin/synogetkeyvalue" ] && echo "/usr/syno/bin/synogetkeyvalue" || echo "/bin/get_key_value")
SKV=$([ -x "/usr/syno/bin/synosetkeyvalue" ] && echo "/usr/syno/bin/synosetkeyvalue" || echo "/bin/set_key_value")

_log(){ echo "[disks] $*"; /bin/logger -p info -t disks "$@"; }

__get_conf_kv(){ $GKV ${ROOT_PATH}/etc.defaults/synoinfo.conf "$1" 2>/dev/null; }
__set_conf_kv(){ for F in ${ROOT_PATH}/etc/synoinfo.conf ${ROOT_PATH}/etc.defaults/synoinfo.conf; do $SKV "$F" "$1" "$2"; done; }

lock_simple(){
    LOCKFILE="/var/run/disks.lock"
    if [ -f "$LOCKFILE" ]; then
        _log "Lock exists, exiting."
        exit 1
    fi
    touch "$LOCKFILE"
    trap 'rm -f "$LOCKFILE"' EXIT
}

checkSynoboot(){
    if [ ! -b /dev/synoboot ]; then
        BOOT=$(ls /dev/sd* 2>/dev/null | head -n1 | sed 's#/dev/##')
        [ -n "$BOOT" ] && ln -sf /dev/$BOOT /dev/synoboot
    fi
}

getUsbPorts(){
    for F in /sys/bus/usb/devices/usb*; do
        [ ! -e "${F}" ] && continue
        [ "$(cat "$F/bDeviceClass")" != "09" ] && continue
        [ "$(cat "$F/speed")" -lt 480 ] && continue
        RBUS=$(cat "$F/busnum"); RCHILDS=$(cat "$F/maxchild")
        HAVE_CHILD=0
        for C in $(seq 1 ${RCHILDS:-0}); do
            if [ -d "$F/$RBUS-$C" ]; then
                [ "$(cat "$F/$RBUS-$C/bDeviceClass")" != "09" ] && continue
                [ "$(cat "$F/$RBUS-$C/speed")" -lt 480 ] && continue
                HAVE_CHILD=1
                CHILDS=$(cat "$F/$RBUS-$C/maxchild")
                for N in $(seq 1 ${CHILDS:-0}); do echo -n "$RBUS-$C.$N "; done
            fi
        done
        [ $HAVE_CHILD -eq 0 ] && for N in $(seq 1 ${RCHILDS:-0}); do echo -n "$RBUS-$N "; done
    done
    echo
}

# check dts slot mapping instead of /usr/syno/bin/syno_slot_mapping
chkSlotMapping() {

  echo "Internal Disk:"
  i=1
  for dev in /sys/block/sata*; do
      devname=$(basename $dev)
      echo "$(printf '%02d' $i): /dev/$devname"
      i=$((i+1))
  done
  echo
  
  echo "Internal SSD Cache:"
  i=1
  for dev in /sys/block/nvme*n*; do
      devname=$(basename $dev)
      echo "$(printf '%02d' $i): /dev/$devname"
      i=$((i+1))
  done

}

dtModel(){
    DEST="/etc/model.dts"
    UNIQUE=$(__get_conf_kv unique)
    echo "/dts-v1/; / { compatible = \"Synology\"; model = \"$UNIQUE\"; version= <0x01>; power_limit=\"\";" > "$DEST"
    # SATA
    for F in /sys/block/sata*; do
        PCIEPATH=$(grep 'pciepath' "$F/device/syno_block_info" 2>/dev/null | cut -d= -f2)
        ATAPORT=$(grep 'ata_port_no' "$F/device/syno_block_info" 2>/dev/null | cut -d= -f2)
        [ -z "$PCIEPATH" ] && continue
        echo " internal_slot@1 { protocol_type = \"sata\"; ahci { pcie_root = \"$PCIEPATH\"; ata_port = <0x$(printf %02X $ATAPORT)>; }; };" >> "$DEST"
    done
    # NVMe
    PL=""
    for F in /sys/block/nvme*; do
        PCIEPATH=$(grep 'pciepath' "$F/device/syno_block_info" 2>/dev/null | cut -d= -f2)
        grep -q "$PCIEPATH" "$DEST" && continue
        PL="${PL},0"
        echo " nvme_slot@1 { pcie_root = \"$PCIEPATH\"; port_type = \"ssdcache\"; };" >> "$DEST"
    done
    [ -n "${PL#,}" ] && sed -i "s/power_limit = \"\";/power_limit = \"${PL#,}\";/" "$DEST"
    # USB
    CNT=0
    for I in $(getUsbPorts); do
        CNT=$((CNT+1))
        echo " usb_slot@$CNT { usb2 { usb_port = \"$I\"; }; usb3 { usb_port = \"$I\"; }; };" >> "$DEST"
    done
    echo "};" >> "$DEST"
    dtc -I dts -O dtb "$DEST" > /etc/model.dtb
    chkSlotMapping
}

nondtModel(){
    echo "[pci]" > /etc/extensionPorts
    for F in /sys/block/nvme*; do
        PCI=$(awk -F= '/PHYSDEVPATH/{print $2}' "$F/uevent" | rev | cut -d/ -f2 | rev)
        echo "pci$((++CNT))=\"$PCI\"" >> /etc/extensionPorts
    done
    __set_conf_kv supportnvme yes
}

nvme_late_patch(){
    MODELS="DS918+ RS1619xs+ DS419+ DS1019+ DS719+ DS1621xs+"
    MODEL=$(cat /proc/sys/kernel/syno_hw_version)
    tmpRoot="/tmpRoot"
    if echo ${MODELS} | grep -q ${MODEL}; then
        SO_FILE="${tmpRoot}/usr/lib/libsynonvme.so.1"
        [ ! -f "${SO_FILE}.bak" ] && cp -vf "${SO_FILE}" "${SO_FILE}.bak"
        cp -vf "${SO_FILE}.bak" "${SO_FILE}"
        num=1
        while read -r N; do
            echo "${num} - ${N}"
            if [ ${num} -eq 1 ]; then
                case "$MODEL" in
                    DS918+) sed -i "s/0000:00:13.1/${N}/" "${SO_FILE}" ;;
                    RS1619xs+) sed -i "s/0000:00:03.2/${N}/" "${SO_FILE}" ;;
                    DS419+|DS1019+) sed -i "s/0000:00:14.1/${N}/" "${SO_FILE}" ;;
                    DS719+|DS1621xs+) sed -i "s/0000:00:01.1/${N}/" "${SO_FILE}" ;;
                esac
            elif [ ${num} -eq 2 ]; then
                case "$MODEL" in
                    DS918+) sed -i "s/0000:00:13.2/${N}/" "${SO_FILE}" ;;
                    RS1619xs+) sed -i "s/0000:00:03.3/${N}/" "${SO_FILE}" ;;
                    DS719+|DS1621xs+) sed -i "s/0000:00:01.0/${N}/" "${SO_FILE}" ;;
                esac
            fi
            num=$((num+1))
        done < /etc/nvmePorts/*
    fi
}

main(){
    lock_simple
    case "$1" in
        --create)
            checkSynoboot
            if [ "$(__get_conf_kv supportportmappingv2)" = "yes" ]; then dtModel; else nondtModel; fi
            ;;
        --update)
            if [ "$(__get_conf_kv supportportmappingv2)" = "yes" ]; then dtModel; else nondtModel; fi
            ;;
        --nvme-late-patch)
            nvme_late_patch
            ;;
        *)
            echo "Usage: $0 {--create|--update|--nvme-late-patch}"
            ;;
    esac
}

main "$@"
