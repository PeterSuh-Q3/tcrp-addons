#!/usr/bin/env sh
# patch-md0 addon
#
# DSM md0 조립 fallback 패치 — FilterInOfSynoPartition/synocheckpartition 이
# 8GB p1 을 제외해 md0 조립이 실패할 때 우회한다.
#
# DSM 버전별 assemble_system_raid.sh 구조:
#   - Main 함수 있음 (구버전) : AssembleMd0IfNeeded 함수를 Main 앞에 삽입 후 호출
#   - Main 함수 없음 (7.4+)   : 파일 끝에 fallback 블록을 직접 추가

_log(){ echo "[patch-md0] $*"; /bin/logger -p info -t patch-md0 "$@"; }

_patch_assemble_md0(){
    local TARGET=/usr/syno/share/assemble_system_raid.sh
    [ -f "$TARGET" ] || { _log "skip: $TARGET not found"; return 0; }
    grep -q "TCRP_MD0_PATCH" "$TARGET" && { _log "already patched"; return 0; }

    if grep -q "^Main$" "$TARGET"; then
        # ── 구버전: Main 함수 앞에 AssembleMd0IfNeeded 삽입 후 Main 내부에서 호출 ──
        local TMPF=/tmp/_tcrp_md0_patch.sh
        cat > "$TMPF" <<'TCRP_EOF'

# TCRP_MD0_PATCH: AssembleMd0IfNeeded fallback (for Main-based DSM)
AssembleMd0IfNeeded() {
    [ -d /sys/block/md0 ] && return 0
    local _p
    for _p in $(ls /dev/sata*p1 /dev/sd*1 2>/dev/null); do
        if /sbin/mdadm -E "${_p}" 2>/dev/null | grep -q "Preferred Minor : 0"; then
            /sbin/mdadm -A --run --force "${RootRaidDevice}" "${_p}" && return 0
        fi
    done
    return 1
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
        _log "patched (Main-style): AssembleMd0IfNeeded inserted before Main"
    else
        # ── 신버전(7.4+): 파일 끝에 fallback 블록 추가 ──
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
        _log "patched (append-style): fallback md0 scan appended"
    fi
}

case "$1" in
    patches)
        _patch_assemble_md0
        ;;
    *)
        echo "Usage: $0 {patches}"
        ;;
esac
