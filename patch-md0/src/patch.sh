#!/usr/bin/env sh
# patch-md0 addon
#
# DSM md0 조립 우회 패치 — TinyCore 에서 expand-md0-8g.sh 로 8GB 확장 후
# md0 슈퍼블록의 device minor 가 sata1p1(8:1) 과 불일치하는 경우(DISK=/dev/sdb 등)
# FilterInOfSynoPartition 이 조립 후보를 제외해 주니어 모드로 진입하는 문제를 우회한다.
#
# 사용 조건 : DISK=/dev/sda 환경(sda1=8:1)이면 이 addon 은 불필요.
#            DISK=/dev/sdb 이상(sdb1=8:17 등)일 때만 설치할 것.

_log(){ echo "[patch-md0] $*"; /bin/logger -p info -t patch-md0 "$@"; }

_patch_assemble_md0(){
    local TARGET=/usr/syno/share/assemble_system_raid.sh
    [ -f "$TARGET" ] || { _log "skip: $TARGET not found"; return 0; }
    grep -q "TCRP_MD0_PATCH" "$TARGET" && { _log "already patched"; return 0; }

    local TMPF=/tmp/_tcrp_md0_patch.sh
    cat > "$TMPF" <<'TCRP_EOF'

# TCRP_MD0_PATCH: AssembleMd0IfNeeded override
AssembleMd0IfNeeded() {
    if HasSysBlock "${RootRaidDevice}"; then
        return 0
    fi

    if GetSortedExistingInstallableDevices "${SystemPartitionNum}" \
        | TryAssembleWithDevices "${RootRaidDevice}"; then
        return 0
    fi

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
    /sbin/mdadm -A --run --force "${RootRaidDevice}" ${_devs} || {
        OutputErr "TCRP: fallback mdadm -A failed on${_devs}"
        return 1
    }
}
TCRP_EOF

    awk -v patch="$TMPF" '
        /^Main$/ {
            while ((getline line < patch) > 0) print line
            close(patch)
        }
        { print }
    ' "$TARGET" > "${TARGET}.tcrp" \
        && mv "${TARGET}.tcrp" "$TARGET" \
        && chmod 755 "$TARGET"

    rm -f "$TMPF"
    _log "patched ${TARGET}: AssembleMd0IfNeeded fallback inserted before Main"
}

case "$1" in
    patches)
        _patch_assemble_md0
        ;;
    *)
        echo "Usage: $0 {patches}"
        ;;
esac
