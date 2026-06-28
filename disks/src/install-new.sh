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

_patch_assemble_md0(){
    # assemble_system_raid.sh 는 "신규 설치" 대상 디스크만 installable 로 간주하며
    # synocheckpartition 을 통과(기존 DSM 파티션 구조 보유)한 디스크를 후보에서 제외한다.
    # TCRP 는 커널 md autodetect(initramfs) 없이 어플 단계 조립에 의존하므로,
    # 기존 설치 디스크(Preferred Minor 0)를 직접 스캔하는 fallback 을 파일 끝에 append 한다.
    # (shell 에서 함수 재정의는 나중 정의가 우선 → 원래 함수를 override)
    local TARGET=/usr/syno/share/assemble_system_raid.sh
    [ -f "$TARGET" ] || { _log "skip patch: $TARGET not found"; return 0; }
    grep -q "TCRP_MD0_PATCH" "$TARGET" && { _log "assemble_system_raid.sh already patched"; return 0; }

    cat >> "$TARGET" <<'TCRP_EOF'

# TCRP_MD0_PATCH: AssembleMd0IfNeeded override
# synocheckpartition 필터가 기존 설치 디스크를 제외하는 문제를 우회한다.
# Preferred Minor 0 인 p1 파티션을 직접 스캔하는 fallback 을 추가.
# 주의: && return 0 대신 if 구문 사용 — set -e 환경에서 파이프라인 실패 시
#       함수가 즉시 종료되어 fallback 에 도달하지 못하는 문제를 방지.
AssembleMd0IfNeeded() {
    if HasSysBlock "${RootRaidDevice}"; then
        return 0
    fi

    # 1. 원래 경로 (신규 설치 대상 디스크)
    if GetSortedExistingInstallableDevices "${SystemPartitionNum}" \
        | TryAssembleWithDevices "${RootRaidDevice}"; then
        return 0
    fi

    # 2. TCRP fallback: Preferred Minor 0 파티션 직접 스캔 (기존 설치 디스크 대응)
    if HasSysBlock "${RootRaidDevice}"; then
        return 0
    fi
    local _p _devs
    _devs=""
    for _p in $(ls /dev/sata*p1 /dev/sd*1 2>/dev/null); do
        if /sbin/mdadm -E "${_p}" 2>/dev/null | grep -q "Preferred Minor : 0"; then
            _devs="${_devs} ${_p}"
        fi
    done
    if [ -z "${_devs}" ]; then
        OutputErr "TCRP: no Preferred Minor 0 partition found for md0"
        return 1
    fi
    Echo "TCRP: fallback md0 assembly from:${_devs}"
    # TryAssembleWithDevices 우회: InsertUUIDArg 가 0.90 메타데이터 UUID 미지원이거나
    # "this device" minor(sdb1=8:17 vs sata1p1=8:1) 불일치로 mdadm -A 가 거부하는 경우.
    # --force 로 직접 조립.
    /sbin/mdadm -A --run --force "${RootRaidDevice}" ${_devs} || {
        OutputErr "TCRP: fallback mdadm -A failed on${_devs}"
        return 1
    }
}
TCRP_EOF
    _log "patched ${TARGET} with TCRP md0 fallback"
}

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
        _patch_assemble_md0
        ;;
    late)
        /usr/bin/disks.sh --update /tmpRoot
        late_stage_nvme_patch
        ;;
    uninstall)
        cleanup_files
        ;;
    *)
        echo "Usage: $0 {modules|patches|late|uninstall}"
        ;;
esac
