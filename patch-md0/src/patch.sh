#!/usr/bin/env sh
# patch-md0 addon
#
# DSM md0 조립 fallback 패치 — FilterInOfSynoPartition 이 조립 후보를 제외하거나
# synocheckpartition 이 8GB p1 을 비표준으로 판단해 md0 조립이 실패할 때 우회한다.
# assemble_system_raid.sh 파일 끝에 fallback 블록을 추가 (Main 함수 불필요).

_log(){ echo "[patch-md0] $*"; /bin/logger -p info -t patch-md0 "$@"; }

_patch_assemble_md0(){
    local TARGET=/usr/syno/share/assemble_system_raid.sh
    [ -f "$TARGET" ] || { _log "skip: $TARGET not found"; return 0; }
    grep -q "TCRP_MD0_PATCH" "$TARGET" && { _log "already patched"; return 0; }

    cat >> "$TARGET" <<'TCRP_EOF'

# TCRP_MD0_PATCH: fallback scan — bypass FilterInOfSynoPartition
# 기존 로직이 md0 조립에 실패한 경우 Preferred Minor=0 파티션을 직접 스캔해 강제 조립한다.
if [ ! -d /sys/block/md0 ]; then
    for _tcrp_p in $(ls /dev/sata*p1 /dev/sd*1 2>/dev/null); do
        if /sbin/mdadm -E "${_tcrp_p}" 2>/dev/null | grep -q "Preferred Minor : 0"; then
            /sbin/mdadm -A --run --force "${RootRaidDevice}" "${_tcrp_p}" && break
        fi
    done
fi
TCRP_EOF

    _log "patched ${TARGET}: fallback md0 scan appended"
}

case "$1" in
    patches)
        _patch_assemble_md0
        ;;
    *)
        echo "Usage: $0 {patches}"
        ;;
esac
