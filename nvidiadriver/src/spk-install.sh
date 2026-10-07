#!/bin/sh
# DSM-side one-shot installer for the pinned, driver-specific NVIDIA SPKs.
# The extension stages only this worker and its small plan; SPKs stay on the
# persistent data volume and are installed only after DSM package services run.
set -u
umask 077

CONF=/usr/local/etc/nvidiadriver-spk.conf
LOG=/var/log/nvidiadriver-spk-install.log
DATA_VOLUME=$(awk -F= '$1 == "DATA_VOLUME" {print $2; exit}' "$CONF" 2>/dev/null)
[ -n "$DATA_VOLUME" ] || DATA_VOLUME=volume1
case "$DATA_VOLUME" in
    volume[0-9]*) DVNUM="${DATA_VOLUME#volume}"; case "$DVNUM" in *[!0-9]*|'') DATA_VOLUME=volume1 ;; esac ;;
    *) DATA_VOLUME=volume1 ;;
esac
ROOT="/$DATA_VOLUME/@appdata/nvidia-driver-installer"
STATE="$ROOT/state"
LOCK=/var/run/nvidiadriver-spk-install.lock

log() { printf '%s nvidiadriver-spk: %s\n' "$(date '+%F %T')" "$*" >> "$LOG" 2>/dev/null; }
state() {
    mkdir -p "$ROOT" 2>/dev/null || return 1
    printf '%s\n' "$1" > "$STATE.tmp" && mv -f "$STATE.tmp" "$STATE"
    log "state=$1${2:+ detail=$2}"
}
value() { awk -F= -v k="$1" '$1 == k {sub(/^[^=]*=/, ""); print; exit}' "$CONF" 2>/dev/null; }
fail() {
    reason=$1
    count=0
    [ -r "$ROOT/failures" ] && count=$(cat "$ROOT/failures" 2>/dev/null)
    case "$count" in ''|*[!0-9]*) count=0 ;; esac
    count=$((count + 1))
    printf '%s\n' "$count" > "$ROOT/failures"
    if [ "$count" -ge 3 ]; then state terminal_failed "$reason (3 attempts)"; else state failed "$reason (attempt $count/3)"; fi
    exit 1
}
get_sha() {
    if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | awk '{print $1}'
    elif command -v openssl >/dev/null 2>&1; then openssl dgst -sha256 "$1" | awk '{print $NF}'
    else return 1; fi
}
info_value() {
    awk -F= -v k="$1" '$1 == k {v=substr($0,index($0,"=")+1); gsub(/^"|"$/, "", v); print v; exit}' "$2"
}
verify_spk() {
    file=$1 pkg=$2 ver=$3 size=$4 sha=$5 extract=$6 platform=$7
    actual_size=$(wc -c < "$file" | tr -d ' ')
    [ "$actual_size" = "$size" ] || { log "size mismatch $(basename "$file"): $actual_size != $size"; return 1; }
    actual_sha=$(get_sha "$file") || { log "SHA-256 utility unavailable"; return 1; }
    [ "$actual_sha" = "$sha" ] || { log "SHA-256 mismatch $(basename "$file")"; return 1; }
    info="$ROOT/info-$(basename "$file").tmp"
    tar -xOf "$file" INFO > "$info" 2>/dev/null || { log "cannot read SPK INFO $(basename "$file")"; return 1; }
    [ "$(info_value package "$info")" = "$pkg" ] || { log "SPK package ID mismatch $(basename "$file")"; return 1; }
    [ "$(info_value version "$info")" = "$ver" ] || { log "SPK version mismatch $(basename "$file")"; return 1; }
    [ "$(info_value extractsize "$info")" = "$extract" ] || { log "SPK extractsize mismatch $(basename "$file")"; return 1; }
    if [ -n "$platform" ]; then
        arch=$(info_value arch "$info")
        case " $arch " in *" $platform "*|*" x86_64 "*) ;; *) log "SPK does not support platform $platform"; return 1 ;; esac
    fi
    rm -f "$info"
    return 0
}
download_spk() {
    role=$1 file=$2 size=$3 sha=$4 pkg=$5 ver=$6 extract=$7 platform=$8
    final="$ROOT/$file"
    part="$final.part"
    if [ -f "$final" ]; then
        if verify_spk "$final" "$pkg" "$ver" "$size" "$sha" "$extract" "$platform"; then return 0; fi
        rm -f "$final"
    fi
    attempt=1
    while [ "$attempt" -le 3 ]; do
        curl --fail --location --silent --show-error --proto '=https' --proto-redir '=https' --connect-timeout 20 --retry 2 --continue-at - \
            "$(value RELEASE_BASE)/$file" -o "$part" || log "$role download attempt $attempt failed"
        if [ -f "$part" ] && verify_spk "$part" "$pkg" "$ver" "$size" "$sha" "$extract" "$platform"; then
            mv -f "$part" "$final" || fail "cannot finalize $role SPK"
            return 0
        fi
        rm -f "$part"
        attempt=$((attempt + 1))
    done
    fail "$role SPK download/validation failed"
}
installed_version() {
    pkg=$1
    info="/var/packages/$pkg/INFO"
    [ -r "$info" ] && info_value version "$info"
}
install_pkg() {
    role=$1 pkg=$2 ver=$3 file=$4
    current=$(installed_version "$pkg" || true)
    if [ "$current" = "$ver" ]; then log "$role already installed at $ver"; return 0; fi
    if [ -n "$current" ]; then
        comparison=$(awk -v a="$ver" -v b="$current" 'BEGIN {
            gsub(/[^0-9]+/, " ", a); gsub(/[^0-9]+/, " ", b)
            na=split(a, aa, " "); nb=split(b, bb, " "); n=(na > nb ? na : nb)
            for (i=1; i<=n; i++) {
                x=(i<=na ? aa[i]+0 : 0); y=(i<=nb ? bb[i]+0 : 0)
                if (x>y) { print 1; exit }
                if (x<y) { print -1; exit }
            }
            print 0
        }')
        [ "$comparison" -ge 0 ] || fail "$role downgrade or version-order check refused: installed=$current selected=$ver"
        [ "$current" != "$ver" ] || return 0
        log "$role package version is $current; applying selected update $ver"
    fi
    /usr/syno/bin/synopkg install "$ROOT/$file" >> "$LOG" 2>&1 || fail "synopkg install failed for $role ($pkg $ver)"
    current=$(installed_version "$pkg" || true)
    [ "$current" = "$ver" ] || fail "$role package did not reach requested version $ver"
    log "$role installed: $pkg $ver"
}
run_install() {
    [ -r "$CONF" ] || { log "plan missing: $CONF"; exit 1; }
    [ -r "$STATE" ] && [ "$(cat "$STATE")" = complete ] && exit 0
    mkdir "$LOCK" 2>/dev/null || exit 0
    trap 'rmdir "$LOCK" 2>/dev/null' EXIT HUP INT TERM
    tries=0
    while [ ! -d "/$DATA_VOLUME" ] && [ "$tries" -lt 60 ]; do sleep 10; tries=$((tries + 1)); done
    [ -d "/$DATA_VOLUME" ] || { state waiting_for_volume; exit 0; }
    mkdir -p "$ROOT" || { state waiting_for_volume; exit 0; }
    chmod 0700 "$ROOT" 2>/dev/null
    tries=0
    while { [ ! -x /usr/syno/bin/synopkg ] || ! /usr/syno/bin/synopkg list >/dev/null 2>&1; } && [ "$tries" -lt 60 ]; do sleep 10; tries=$((tries + 1)); done
    { [ -x /usr/syno/bin/synopkg ] && /usr/syno/bin/synopkg list >/dev/null 2>&1; } || { state waiting_for_package_service; exit 0; }

    platform=$(value PLATFORM)
    driver_pkg=$(value DRIVER_PACKAGE); driver_ver=$(value DRIVER_VERSION); driver_file=$(value DRIVER_FILE)
    driver_size=$(value DRIVER_SIZE); driver_sha=$(value DRIVER_SHA); driver_extract=$(value DRIVER_EXTRACT)
    monitor_pkg=$(value MONITOR_PACKAGE); monitor_ver=$(value MONITOR_VERSION); monitor_file=$(value MONITOR_FILE)
    monitor_size=$(value MONITOR_SIZE); monitor_sha=$(value MONITOR_SHA); monitor_extract=$(value MONITOR_EXTRACT)
    runtime_enabled=$(value RUNTIME_ENABLED); ffmpeg_enabled=$(value FFMPEG_ENABLED)
    [ -n "$driver_pkg" ] && [ -n "$driver_file" ] || fail "driver entry missing from plan"

    total_bytes=$(( $(value DRIVER_SIZE) + $(value MONITOR_SIZE) ))
    max_extract=$(value DRIVER_EXTRACT)
    if [ "$runtime_enabled" = true ]; then total_bytes=$((total_bytes + $(value RUNTIME_SIZE))); [ "$(value RUNTIME_EXTRACT)" -le "$max_extract" ] || max_extract=$(value RUNTIME_EXTRACT); fi
    if [ "$ffmpeg_enabled" = true ]; then total_bytes=$((total_bytes + $(value FFMPEG_SIZE))); [ "$(value FFMPEG_EXTRACT)" -le "$max_extract" ] || max_extract=$(value FFMPEG_EXTRACT); fi
    required_kb=$(( (2 * total_bytes / 1024) + max_extract + 1048576 ))
    free_kb=$(df -Pk "$ROOT" | awk 'END {print $4}')
    case "$free_kb" in ''|*[!0-9]*) state waiting_for_space "free-space check unavailable"; exit 0 ;; esac
    [ "$free_kb" -ge "$required_kb" ] || { state waiting_for_space "need ${required_kb}KiB, have ${free_kb}KiB"; exit 0; }

    # Refuse implicit migration between variant package IDs. A K4 DSM migration
    # changes package IDs and must be handled explicitly, never by side install.
    for other in syno-nvidia-driver-kver5 syno-nvidia-driver-kver4-dsm72 syno-nvidia-driver-kver4-dsm70; do
        [ "$other" = "$driver_pkg" ] && continue
        [ -r "/var/packages/$other/INFO" ] && fail "different driver variant $other is installed; migration needs manual handling"
    done

    state downloading
    download_spk driver "$driver_file" "$driver_size" "$driver_sha" "$driver_pkg" "$driver_ver" "$driver_extract" "$platform"
    download_spk monitor "$(value MONITOR_FILE)" "$(value MONITOR_SIZE)" "$(value MONITOR_SHA)" \
        "$monitor_pkg" "$monitor_ver" "$monitor_extract" "$platform"
    if [ "$runtime_enabled" = true ]; then
        download_spk runtime "$(value RUNTIME_FILE)" "$(value RUNTIME_SIZE)" "$(value RUNTIME_SHA)" \
            "$(value RUNTIME_PACKAGE)" "$(value RUNTIME_VERSION)" "$(value RUNTIME_EXTRACT)" "$platform"
    fi
    if [ "$ffmpeg_enabled" = true ]; then
        download_spk ffmpeg "$(value FFMPEG_FILE)" "$(value FFMPEG_SIZE)" "$(value FFMPEG_SHA)" \
            "$(value FFMPEG_PACKAGE)" "$(value FFMPEG_VERSION)" "$(value FFMPEG_EXTRACT)" "$platform"
    fi

    # Download and validate every selected asset before the first package write.
    install_pkg driver "$driver_pkg" "$driver_ver" "$driver_file"
    install_pkg monitor "$monitor_pkg" "$monitor_ver" "$monitor_file"
    module_version=""
    [ -r /sys/module/nvidia/version ] && module_version=$(cat /sys/module/nvidia/version)
    if [ "$module_version" != "$(value DRIVER_BRANCH_VERSION)" ]; then
        state installed_pending_reboot "driver installed; loaded=${module_version:-none}"
        exit 0
    fi
    state driver_active
    if [ "$runtime_enabled" = true ]; then
        install_pkg runtime "$(value RUNTIME_PACKAGE)" "$(value RUNTIME_VERSION)" "$(value RUNTIME_FILE)"
    fi
    if [ "$ffmpeg_enabled" = true ]; then
        install_pkg ffmpeg "$(value FFMPEG_PACKAGE)" "$(value FFMPEG_VERSION)" "$(value FFMPEG_FILE)"
    fi
    printf 'complete\n' > "$STATE.tmp" && mv -f "$STATE.tmp" "$STATE"
    rm -f "$ROOT/failures"
    log "bundle complete"
}

case "${1:-start}" in
    start) (/bin/sh "$0" run >/dev/null 2>&1 </dev/null &) ;;
    run) run_install ;;
    *) exit 2 ;;
esac
