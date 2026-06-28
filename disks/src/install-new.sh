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
if [ -x "/bin/set_key_value" ]; then
    SKV="/bin/set_key_value"
elif [ -x "/usr/syno/bin/synosetkeyvalue" ]; then
    SKV="/usr/syno/bin/synosetkeyvalue"
else
    SKV="set_key_value"
fi
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

# [DISABLED] _patch_assemble_md0
# expand-md0-8g.sh 의 Phase 4 가 --zero-superblock + --create 를 사용했기 때문에
# TinyCore 디바이스 번호(sdb1=8:17)가 슈퍼블록에 기록되어 DSM(sata1p1=8:1)과
# 불일치 → 주니어 모드 진입 문제를 우회하기 위해 추가한 패치.
# Phase 4 를 --grow 방식으로 교체하여 슈퍼블록을 재생성하지 않으므로 이 패치는 불필요.
# _patch_assemble_md0(){ ... }

cleanup_files(){
    rm -f /usr/bin/disks.sh /usr/bin/dtc /etc/model.dtb
    rm -f /usr/lib/udev/rules.d/04-system-disk-dtb.rules
    rm -rf /etc/nvmePorts
}

case "$1" in
    modules)
        ./disks.sh --modules
        ;;
    patches)
        copy_files
        sync_synoinfo_keys
        /usr/bin/disks.sh --create
        # _patch_assemble_md0  # DISABLED: expand-md0-8g.sh --grow 방식으로 대체됨
        ;;
    late)
        /usr/bin/disks.sh --update /tmpRoot
        late_stage_nvme_patch
        # [DISABLED] md2 수동 조립 + LVM vgchange
        # expand-md0-8g.sh 의 --update=devicesize 재조립으로 md2 슈퍼블록 Name 이
        # TinyCore 호스트명으로 기록되어 DSM 자동 조립이 실패하는 문제를 우회하기 위해 추가.
        # expand-md0-8g.sh Phase 4 를 --grow 방식으로 교체 후 md2 는 원본 슈퍼블록 유지.
        # DSM 정상 부팅 시 커널/init 이 md2 조립 및 LVM 활성화를 자체적으로 처리함.
        ;;
    uninstall)
        cleanup_files
        ;;
    *)
        echo "Usage: $0 {modules|patches|late|uninstall}"
        ;;
esac
