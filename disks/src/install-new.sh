#!/usr/bin/env sh
# RR+mshell 완전 통합 install.sh (install, flock 제거 버전)

set_key_value() {
    local file="$1"
    local key="$2"
    local value="$3"

    [ ! -f "$file" ] && touch "$file"

    value=$(echo "$value" | sed 's/[\/&]/\\&/g')
    
    if grep -q "^${key}=" "$file"; then
        # 기존 키 업데이트
        sed -i "s/^${key}=.*/${key}=${value}/" "$file"
    else
        # 새로운 키 추가
        echo "${key}=${value}" >> "$file"
    fi
}

GKV=$([ -x "/usr/syno/bin/synogetkeyvalue" ] && echo "/usr/syno/bin/synogetkeyvalue" || echo "/bin/get_key_value")
SKV="set_key_value"
_log(){ echo "[install] $*"; /bin/logger -p info -t install "$@"; }

copy_files(){
    cp -pf ./disks.sh /usr/bin/disks.sh && chmod 755 /usr/bin/disks.sh
    mkdir -p /usr/lib/udev/rules.d
    cat > /usr/lib/udev/rules.d/04-system-disk-dtb.rules <<"EOF"
ACTION=="add", SUBSYSTEM=="block", ENV{DEVTYPE}=="disk", ENV{DEVNAME}=="/dev/nvme*|/dev/sas*|/dev/usb*|/dev/sd*|/dev/sata*", PROGRAM=="/usr/bin/disks.sh --update %E{DEVNAME}"
EOF
}

sync_synoinfo_keys(){
    KVLIST="maxdisks supportnvme support_m2_pool usbportcfg esataportcfg internalportcfg supportportmappingv2"
    for K in $KVLIST; do
        V=$($GKV /etc.defaults/synoinfo.conf $K)
        for F in /etc/synoinfo.conf /etc.defaults/synoinfo.conf; do $SKV "$F" "$K" "$V"; done
        _log "$K=$V"
    done
}

late_stage_nvme_patch(){
    /usr/bin/disks.sh --nvme-late-patch
}

cleanup_files(){
    rm -f /usr/bin/disks.sh /usr/bin/dtc /etc/model.dtb
    rm -f /usr/lib/udev/rules.d/04-system-disk-dtb.rules
    rm -rf /etc/nvmePorts
}

case "$1" in
    patches)
        copy_files
        sync_synoinfo_keys
        /usr/bin/disks.sh --create
        ;;
    late)
        /usr/bin/disks.sh --update
        late_stage_nvme_patch
        ;;
    uninstall)
        cleanup_files
        ;;
    *)
        echo "Usage: $0 {patches|late|uninstall}"
        ;;
esac
