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
    # assemble_system_raid.sh 는 파일 끝에서 Main 을 직접 호출한다(^Main$).
    # append 방식으로 override 를 추가하면 Main 호출 이후에 함수가 정의되어 무시됨.
    # 따라서 awk 로 ^Main$ 행 바로 앞에 override 를 삽입해야 한다.
    local TARGET=/usr/syno/share/assemble_system_raid.sh
    [ -f "$TARGET" ] || { _log "skip patch: $TARGET not found"; return 0; }
    grep -q "TCRP_MD0_PATCH" "$TARGET" && { _log "assemble_system_raid.sh already patched"; return 0; }

    local TMPF=/tmp/_tcrp_md0_patch.sh
    cat > "$TMPF" <<'TCRP_EOF'

# TCRP_MD0_PATCH: AssembleMd0IfNeeded override
# synocheckpartition 필터가 기존 설치 디스크를 제외하는 문제를 우회한다.
# Preferred Minor 0 인 p1 파티션을 직접 스캔하는 fallback 을 추가.
# 주의: if 구문 사용 — set -e 환경에서 파이프라인 실패 시 && return 0 이
#       함수를 즉시 종료하여 fallback 에 도달하지 못하는 문제를 방지.
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
    # TryAssembleWithDevices 우회: InsertUUIDArg(0.90 UUID 미지원) 또는
    # device minor 불일치(sdb1=8:17 vs sata1p1=8:1) 로 mdadm -A 거부 대응.
    /sbin/mdadm -A --run --force "${RootRaidDevice}" ${_devs} || {
        OutputErr "TCRP: fallback mdadm -A failed on${_devs}"
        return 1
    }
}
TCRP_EOF

    # ^Main$ (standalone 호출) 바로 앞에 삽입 — 이 시점에 override 가 정의되어야
    # Main() 내부에서 AssembleMd0IfNeeded 를 호출할 때 override 가 사용됨.
    awk -v patch="$TMPF" '
        /^Main$/ {
            while ((getline line < patch) > 0) print line
            close(patch)
        }
        { print }
    ' "$TARGET" > "${TARGET}.tcrp" && mv "${TARGET}.tcrp" "$TARGET" && chmod 755 "$TARGET"

    rm -f "$TMPF"
    _log "patched ${TARGET} with TCRP md0 fallback (inserted before Main call)"
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
        # 1.2 메타데이터 RAID(md2 등 데이터 풀)는 커널 자동 인식 안 됨.
        # DSM 스토리지 데몬 초기화 전에 조립해야 풀이 정상 인식됨.
        # late 단계에서 대부분 바이너리는 /tmpRoot 하위에 존재하므로 경로 우선순위 탐색.
        _mdadm=$(which mdadm 2>/dev/null || echo "")
        [ -z "$_mdadm" ] && [ -x /tmpRoot/sbin/mdadm ] && _mdadm=/tmpRoot/sbin/mdadm
        [ -z "$_mdadm" ] && [ -x /sbin/mdadm ] && _mdadm=/sbin/mdadm
        [ -n "$_mdadm" ] && $_mdadm --assemble --scan --run 2>/dev/null || true
        ;;
    uninstall)
        cleanup_files
        ;;
    *)
        echo "Usage: $0 {modules|patches|late|uninstall}"
        ;;
esac
