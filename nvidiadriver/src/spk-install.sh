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
ASSET_STATE="$ROOT/installed-assets"
LOCK=/var/run/nvidiadriver-spk-install.lock
SYNOPKG=/usr/syno/bin/synopkg

log() { printf '%s nvidiadriver-spk: %s\n' "$(date '+%F %T')" "$*" >> "$LOG" 2>/dev/null; }
state() {
    mkdir -p "$ROOT" 2>/dev/null || return 1
    printf '%s\n' "$1" > "$STATE.tmp" && mv -f "$STATE.tmp" "$STATE"
    log "state=$1${2:+ detail=$2}"
}
value() { awk -F= -v k="$1" '$1 == k {sub(/^[^=]*=/, ""); print; exit}' "$CONF" 2>/dev/null; }
asset_value() { awk -F= -v k="$1" '$1 == k {sub(/^[^=]*=/, ""); print; exit}' "$ASSET_STATE" 2>/dev/null; }
asset_set() {
    key=$1 value=$2 tmp="$ASSET_STATE.tmp.$$"
    mkdir -p "$ROOT" || return 1
    { awk -F= -v k="$key" '$1 != k {print}' "$ASSET_STATE" 2>/dev/null; printf '%s=%s\n' "$key" "$value"; } > "$tmp" \
        && chmod 0600 "$tmp" && mv -f "$tmp" "$ASSET_STATE"
}
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
sha256_stream() {
    if command -v sha256sum >/dev/null 2>&1; then sha256sum | awk '{print $1}'
    elif command -v openssl >/dev/null 2>&1; then openssl dgst -sha256 | awk '{print $NF}'
    else return 1; fi
}
payload_member() {
    case "$1" in
        driver) printf './lib/modules/%s/nvidia.ko\n' "$2" ;;
        monitor) printf './bin/syno-nvidia-gpu-monitor\n' ;;
        runtime) printf './runtime/bin/nvidia-container-runtime\n' ;;
        ffmpeg) printf './bin/ffmpeg\n' ;;
        *) return 1 ;;
    esac
}
spk_payload_sha() {
    spk=$1 member=$2
    tar -xOf "$spk" package.tgz 2>/dev/null | tar -xOzf - "$member" 2>/dev/null | sha256_stream
}
verify_recorded_payload() {
    role=$1 pkg=$2 ver=$3 sha=$4 platform=$5
    [ "$(asset_value "${role}_package")" = "$pkg" ] \
        && [ "$(asset_value "${role}_version")" = "$ver" ] \
        && [ "$(asset_value "${role}_sha256")" = "$sha" ] || return 1
    info="/var/packages/$pkg/INFO"
    current=$(installed_version "$pkg" || true)
    [ "$current" = "$ver" ] || { log "$role installed INFO version mismatch: expected=$ver actual=${current:-missing}"; return 1; }
    member=$(payload_member "$role" "$platform") || return 1
    installed="/var/packages/$pkg/target/${member#./}"
    [ -s "$installed" ] || { log "$role installed payload missing: $installed"; return 1; }
    expected_payload=$(asset_value "${role}_payload_sha256")
    actual_payload=$(get_sha "$installed") || return 1
    log "$role installed payload check: package=$pkg expected_version=$ver actual_version=$current asset_sha256=$sha expected_payload_sha256=${expected_payload:-unknown} actual_payload_sha256=$actual_payload"
    [ -n "$expected_payload" ] && [ "$actual_payload" = "$expected_payload" ]
}
record_installed_payload() {
    role=$1 pkg=$2 ver=$3 sha=$4 payload_sha=$5
    asset_set "${role}_package" "$pkg" \
        && asset_set "${role}_version" "$ver" \
        && asset_set "${role}_sha256" "$sha" \
        && asset_set "${role}_payload_sha256" "$payload_sha"
}
verify_spk() {
    role=$1 file=$2 pkg=$3 ver=$4 size=$5 sha=$6 extract=$7 platform=$8
    actual_size=$(wc -c < "$file" | tr -d ' ')
    [ "$actual_size" = "$size" ] || { log "size mismatch $(basename "$file"): $actual_size != $size"; return 1; }
    actual_sha=$(get_sha "$file") || { log "SHA-256 utility unavailable"; return 1; }
    [ "$actual_sha" = "$sha" ] || { log "SHA-256 mismatch $(basename "$file")"; return 1; }
    info="$ROOT/info-$(basename "$file").tmp"
    tar -xOf "$file" INFO > "$info" 2>/dev/null || { log "cannot read SPK INFO $(basename "$file")"; return 1; }
    [ "$(info_value package "$info")" = "$pkg" ] || { log "SPK package ID mismatch $(basename "$file")"; return 1; }
    [ "$(info_value version "$info")" = "$ver" ] || { log "SPK version mismatch $(basename "$file")"; return 1; }
    [ "$(info_value extractsize "$info")" = "$extract" ] || { log "SPK extractsize mismatch $(basename "$file")"; return 1; }
    expected_payload_md5=$(info_value checksum "$info")
    [ -n "$expected_payload_md5" ] || { log "SPK package.tgz checksum missing $(basename "$file")"; return 1; }
    tar -tf "$file" 2>/dev/null | grep -qx 'package.tgz' || { log "SPK package.tgz missing $(basename "$file")"; return 1; }
    actual_payload_md5=$(tar -xOf "$file" package.tgz 2>/dev/null | md5sum | awk '{print $1}')
    [ "$actual_payload_md5" = "$expected_payload_md5" ] || {
        log "SPK payload checksum mismatch $(basename "$file"): expected=$expected_payload_md5 actual=$actual_payload_md5"; return 1; }
    member=$(payload_member "$role" "$platform") || { log "unknown SPK role $role"; return 1; }
    actual_payload_sha=$(spk_payload_sha "$file" "$member") || { log "cannot inspect $role payload member $member"; return 1; }
    [ -n "$actual_payload_sha" ] || { log "empty $role payload member $member"; return 1; }
    if [ -n "$platform" ]; then
        arch=$(info_value arch "$info")
        case " $arch " in *" $platform "*|*" x86_64 "*) ;; *) log "SPK does not support platform $platform"; return 1 ;; esac
    fi
    rm -f "$info"
    log "$role SPK verified: package=$pkg version=$ver expected_asset_sha256=$sha actual_asset_sha256=$actual_sha package_tgz_md5=$actual_payload_md5 payload_member=$member payload_sha256=$actual_payload_sha"
    return 0
}
download_spk() {
    role=$1 file=$2 size=$3 sha=$4 pkg=$5 ver=$6 extract=$7 platform=$8
    final="$ROOT/$file"
    part="$final.part"
    if [ -f "$final" ]; then
        if verify_spk "$role" "$final" "$pkg" "$ver" "$size" "$sha" "$extract" "$platform"; then return 0; fi
        rm -f "$final"
    fi
    attempt=1
    while [ "$attempt" -le 3 ]; do
        curl --fail --location --silent --show-error --proto '=https' --proto-redir '=https' --connect-timeout 20 --retry 2 --continue-at - \
            "$(value RELEASE_BASE)/$file" -o "$part" || log "$role download attempt $attempt failed"
        if [ -f "$part" ] && verify_spk "$role" "$part" "$pkg" "$ver" "$size" "$sha" "$extract" "$platform"; then
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
verify_installed_payload() {
    role=$1 pkg=$2 ver=$3 file=$4 sha=$5 platform=$6
    current=$(installed_version "$pkg" || true)
    [ "$current" = "$ver" ] || { log "$role installed INFO version mismatch: expected=$ver actual=${current:-missing}"; return 1; }
    member=$(payload_member "$role" "$platform") || return 1
    installed="/var/packages/$pkg/target/${member#./}"
    [ -s "$installed" ] || { log "$role installed payload missing: $installed"; return 1; }
    expected_payload=$(spk_payload_sha "$ROOT/$file" "$member") || return 1
    actual_payload=$(get_sha "$installed") || return 1
    log "$role install verification: expected_version=$ver actual_version=$current expected_asset_sha256=$sha expected_payload_sha256=$expected_payload actual_payload_sha256=$actual_payload path=$installed"
    [ -n "$expected_payload" ] && [ "$actual_payload" = "$expected_payload" ] || return 1
    record_installed_payload "$role" "$pkg" "$ver" "$sha" "$actual_payload"
}
wait_for_package_manager() {
    # DSM may report synopkg as callable while package units are still
    # transitioning in parallel during boot. Match aeudev's settle window.
    log "waiting 30 seconds for DSM package services to settle before installation"
    sleep 30
}
install_with_retry() {
    role=$1 spk=$2 attempt=1
    while [ "$attempt" -le 8 ]; do
        result=$("$SYNOPKG" install "$spk" 2>&1)
        status=$?
        printf '%s\n' "$result" >> "$LOG" 2>/dev/null
        [ "$status" -eq 0 ] && return 0

        # DSM returns code 263 while an installed package is activating or
        # deactivating. Treat only that known transition as transient.
        if printf '%s' "$result" | grep -Eq '"code":263|code.?263|activating/deactivating'; then
            log "$role package manager transition (attempt $attempt/8); retrying in 15 seconds"
            attempt=$((attempt + 1))
            sleep 15
            continue
        fi

        log "$role synopkg install failed with exit=$status: $result"
        return "$status"
    done
    log "$role synopkg install exhausted 8 retries for $spk"
    return 1
}
start_with_retry() {
    role=$1 pkg=$2 attempt=1
    while [ "$attempt" -le 8 ]; do
        if [ "$role" = driver ] && [ "$attempt" -gt 1 ] && verify_driver_activation; then
            return 0
        fi
        result=$("$SYNOPKG" start "$pkg" 2>&1)
        status=$?
        printf '%s\n' "$result" >> "$LOG" 2>/dev/null
        if [ "$status" -eq 0 ]; then
            log "$role synopkg start succeeded: $pkg"
            if [ "$role" != driver ]; then return 0; fi
        elif [ "$role" != driver ]; then
            # Non-driver packages are retried only for DSM's known transition.
            if printf '%s' "$result" | grep -Eq '"code":263|code.?263|activating/deactivating'; then
                log "$role package start transition (attempt $attempt/8); retrying in 15 seconds"
                attempt=$((attempt + 1))
                sleep 15
                continue
            fi
            log "$role synopkg start was not accepted (exit=$status): $result"
            return 1
        fi

        # For the driver, command status is not the success criterion: DSM may
        # reject manual start for startable=no, or return before device setup.
        # Check the actual loaded module and character devices on every round,
        # then retry start only while the expected NVIDIA device is not ready.
        if verify_driver_activation; then return 0; fi
        observed=""
        [ -r /sys/module/nvidia/version ] && observed=$(cat /sys/module/nvidia/version 2>/dev/null)
        expected=$(value DRIVER_BRANCH_VERSION)
        if [ -n "$observed" ] && [ -n "$expected" ] && [ "$observed" != "$expected" ]; then
            log "driver start retry stopped: a different NVIDIA module is active (expected=$expected actual=$observed)"
            return 1
        fi
        log "driver start attempt $attempt/8 did not produce the expected NVIDIA module/device nodes (synopkg_exit=$status); retrying in 10 seconds"
        attempt=$((attempt + 1))
        [ "$attempt" -le 8 ] && sleep 10
    done
    log "$role synopkg start exhausted 8 attempts without verified NVIDIA device nodes"
    return 1
}
install_pkg() {
    role=$1 pkg=$2 ver=$3 file=$4 sha=$5 force_reinstall=${6:-false}
    current=$(installed_version "$pkg" || true)
    if [ "$force_reinstall" != true ] && [ "$current" = "$ver" ] \
        && verify_recorded_payload "$role" "$pkg" "$ver" "$sha" "$(value PLATFORM)"; then
        log "$role already installed with matching version and asset digest: $pkg $ver sha256=$sha"
        start_with_retry "$role" "$pkg" || true
        return 0
    fi
    if [ "$force_reinstall" = true ] && [ "$current" = "$ver" ]; then
        log "$role delayed activation retry: reinstalling the same verified SPK once for $pkg $ver sha256=$sha"
    fi
    if [ "$current" = "$ver" ]; then
        log "$role installed INFO version is unchanged but asset/payload digest is stale or unknown; reapplying the selected SPK: version=$ver expected_sha256=$sha recorded_sha256=$(asset_value "${role}_sha256")"
    fi
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
        [ "$current" = "$ver" ] || log "$role package version is $current; applying selected update $ver"
    fi
    install_with_retry "$role" "$ROOT/$file" || fail "synopkg install failed for $role ($pkg $ver) after transient-error retries"
    current=$(installed_version "$pkg" || true)
    [ "$current" = "$ver" ] || fail "$role package did not reach requested version $ver"
    verify_installed_payload "$role" "$pkg" "$ver" "$file" "$sha" "$(value PLATFORM)" \
        || fail "$role installed package version is present but payload verification failed ($pkg $ver sha256=$sha)"
    start_with_retry "$role" "$pkg" || true
    log "$role installed and payload verified: $pkg $ver asset_sha256=$sha"
}
verify_driver_activation() {
    expected=$(value DRIVER_BRANCH_VERSION)
    actual=""
    [ -r /sys/module/nvidia/version ] && actual=$(cat /sys/module/nvidia/version 2>/dev/null)
    log "driver activation check: expected_module_version=${expected:-unknown} actual_module_version=${actual:-missing}"
    [ -n "$expected" ] && [ "$actual" = "$expected" ] || return 1
    grep -q '^nvidia ' /proc/modules 2>/dev/null || {
        log "driver activation failed: nvidia is absent from /proc/modules"
        return 1
    }
    [ -c /dev/nvidiactl ] || {
        log "driver activation failed: /dev/nvidiactl is missing or not a character device"
        return 1
    }
    node_found=false
    for node in /dev/nvidia[0-9]*; do
        [ -c "$node" ] && { node_found=true; break; }
    done
    [ "$node_found" = true ] || {
        log "driver activation failed: no numbered /dev/nvidiaN character device exists"
        return 1
    }
    log "driver activation verified: module=$actual nvidiactl=present gpu_node=$node"
    return 0
}
wait_for_driver_activation() {
    attempt=1
    while [ "$attempt" -le 6 ]; do
        if verify_driver_activation; then return 0; fi
        if [ -r /sys/module/nvidia/version ]; then
            observed=$(cat /sys/module/nvidia/version 2>/dev/null)
            if [ -n "$observed" ] && [ "$observed" != "$(value DRIVER_BRANCH_VERSION)" ]; then
                log "activation wait stopped: another NVIDIA module version is active ($observed)"
                return 2
            fi
        fi
        [ "$attempt" -eq 6 ] || sleep 10
        attempt=$((attempt + 1))
    done
    return 1
}
ensure_driver_activation() {
    expected="$(value DRIVER_BRANCH_VERSION)"
    actual=""
    [ -r /sys/module/nvidia/version ] && actual=$(cat /sys/module/nvidia/version 2>/dev/null)
    if [ -n "$actual" ] && [ "$actual" != "$expected" ]; then
        log "driver activation requires reboot: expected=$expected actual=$actual asset_sha256=$driver_sha"
        state installed_pending_reboot "expected=$expected loaded=$actual"
        return 2
    fi
    if wait_for_driver_activation; then return 0; else wait_rc=$?; fi
    [ "$wait_rc" -eq 2 ] && {
        actual=$(cat /sys/module/nvidia/version 2>/dev/null)
        state installed_pending_reboot "expected=$expected loaded=${actual:-unknown}"
        return 2
    }

    retry_record=$(asset_value activation_retry)
    if [ "$retry_record" = "$bundle_sha|1" ]; then
        log "delayed activation reinstall already used for this bundle; not retrying again: bundle_sha256=$bundle_sha"
        state activation_failed "driver remains inactive after one delayed reinstall attempt"
        return 1
    fi
    log "driver not active after initial grace period; waiting 60 seconds before one bounded reinstall retry"
    state activation_retry_wait "bundle_sha256=$bundle_sha"
    sleep 60
    if wait_for_driver_activation; then return 0; else wait_rc=$?; fi
    [ "$wait_rc" -eq 2 ] && {
        actual=$(cat /sys/module/nvidia/version 2>/dev/null)
        state installed_pending_reboot "expected=$expected loaded=${actual:-unknown}"
        return 2
    }

    asset_set activation_retry "$bundle_sha|1" || {
        state activation_failed "cannot persist bounded activation retry marker"
        return 1
    }
    state activation_retrying "reinstalling verified driver SPK once after delay"
    install_pkg driver "$driver_pkg" "$driver_ver" "$driver_file" "$driver_sha" true || return 1
    if wait_for_driver_activation; then return 0; else wait_rc=$?; fi
    if [ "$wait_rc" -eq 2 ]; then
        actual=$(cat /sys/module/nvidia/version 2>/dev/null)
        state installed_pending_reboot "expected=$expected loaded=${actual:-unknown}"
        return 2
    fi
    log "driver still inactive after delayed reinstall: expected_module_version=$expected asset_sha256=$driver_sha"
    state activation_failed "module/device activation failed after bounded delayed reinstall"
    return 1
}
verify_complete_bundle() {
    verify_driver_activation || return 1
    verify_recorded_payload driver "$driver_pkg" "$driver_ver" "$driver_sha" "$platform" || return 1
    verify_recorded_payload monitor "$monitor_pkg" "$monitor_ver" "$monitor_sha" "$platform" || return 1
    if [ "$runtime_enabled" = true ]; then
        verify_recorded_payload runtime "$(value RUNTIME_PACKAGE)" "$(value RUNTIME_VERSION)" \
            "$(value RUNTIME_SHA)" "$platform" || return 1
    fi
    if [ "$ffmpeg_enabled" = true ]; then
        verify_recorded_payload ffmpeg "$(value FFMPEG_PACKAGE)" "$(value FFMPEG_VERSION)" \
            "$(value FFMPEG_SHA)" "$platform" || return 1
    fi
    return 0
}
run_install() {
    [ -r "$CONF" ] || { log "plan missing: $CONF"; exit 1; }
    mkdir "$LOCK" 2>/dev/null || exit 0
    trap 'rmdir "$LOCK" 2>/dev/null' EXIT HUP INT TERM
    tries=0
    while [ ! -d "/$DATA_VOLUME" ] && [ "$tries" -lt 60 ]; do sleep 10; tries=$((tries + 1)); done
    [ -d "/$DATA_VOLUME" ] || { state waiting_for_volume; exit 0; }
    mkdir -p "$ROOT" || { state waiting_for_volume; exit 0; }
    chmod 0700 "$ROOT" 2>/dev/null
    tries=0
    while { [ ! -x "$SYNOPKG" ] || ! "$SYNOPKG" list >/dev/null 2>&1; } && [ "$tries" -lt 60 ]; do sleep 10; tries=$((tries + 1)); done
    { [ -x "$SYNOPKG" ] && "$SYNOPKG" list >/dev/null 2>&1; } || { state waiting_for_package_service; exit 0; }

    platform=$(value PLATFORM)
    driver_pkg=$(value DRIVER_PACKAGE); driver_ver=$(value DRIVER_VERSION); driver_file=$(value DRIVER_FILE)
    driver_size=$(value DRIVER_SIZE); driver_sha=$(value DRIVER_SHA); driver_extract=$(value DRIVER_EXTRACT)
    monitor_pkg=$(value MONITOR_PACKAGE); monitor_ver=$(value MONITOR_VERSION); monitor_file=$(value MONITOR_FILE)
    monitor_size=$(value MONITOR_SIZE); monitor_sha=$(value MONITOR_SHA); monitor_extract=$(value MONITOR_EXTRACT)
    runtime_enabled=$(value RUNTIME_ENABLED); ffmpeg_enabled=$(value FFMPEG_ENABLED)
    [ -n "$driver_pkg" ] && [ -n "$driver_file" ] || fail "driver entry missing from plan"
    [ -n "$driver_sha" ] && [ -n "$monitor_sha" ] || fail "required SPK asset digest missing from plan"
    if [ "$runtime_enabled" = true ]; then [ -n "$(value RUNTIME_SHA)" ] || fail "runtime SPK asset digest missing from plan"; fi
    if [ "$ffmpeg_enabled" = true ]; then [ -n "$(value FFMPEG_SHA)" ] || fail "FFmpeg SPK asset digest missing from plan"; fi

    bundle_sha=$(printf '%s\n' \
        "platform=$platform" \
        "driver=$driver_pkg|$driver_ver|$driver_file|$driver_size|$driver_sha" \
        "monitor=$monitor_pkg|$monitor_ver|$monitor_file|$monitor_size|$monitor_sha" \
        "runtime_enabled=$runtime_enabled|$(value RUNTIME_PACKAGE)|$(value RUNTIME_VERSION)|$(value RUNTIME_FILE)|$(value RUNTIME_SIZE)|$(value RUNTIME_SHA)" \
        "ffmpeg_enabled=$ffmpeg_enabled|$(value FFMPEG_PACKAGE)|$(value FFMPEG_VERSION)|$(value FFMPEG_FILE)|$(value FFMPEG_SIZE)|$(value FFMPEG_SHA)" \
        | sha256_stream) || fail "cannot calculate selected SPK bundle digest"

    if [ -r "$STATE" ] && [ "$(cat "$STATE")" = complete ]; then
        recorded_bundle_sha=$(asset_value bundle_sha256)
        # A prior run may have installed everything but left a package stopped.
        # Re-assert package start before accepting the cached complete state.
        start_with_retry driver "$driver_pkg" || true
        start_with_retry monitor "$monitor_pkg" || true
        if [ "$runtime_enabled" = true ]; then
            start_with_retry runtime "$(value RUNTIME_PACKAGE)" || true
        fi
        if [ "$ffmpeg_enabled" = true ]; then
            start_with_retry ffmpeg "$(value FFMPEG_PACKAGE)" || true
        fi
        if [ "$recorded_bundle_sha" = "$bundle_sha" ] && verify_complete_bundle; then
            log "selected bundle unchanged and installed payload/driver activation verified: bundle_sha256=$bundle_sha"
            exit 0
        fi
        log "complete marker invalidated: expected_bundle_sha256=$bundle_sha recorded_bundle_sha256=${recorded_bundle_sha:-unknown}; revalidating selected assets"
        state revalidating
    fi

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
    wait_for_package_manager
    install_pkg driver "$driver_pkg" "$driver_ver" "$driver_file" "$driver_sha"
    install_pkg monitor "$monitor_pkg" "$monitor_ver" "$monitor_file" "$monitor_sha"
    ensure_driver_activation || { activation_rc=$?; [ "$activation_rc" -eq 2 ] && exit 0; exit 1; }
    state driver_active
    if [ "$runtime_enabled" = true ]; then
        install_pkg runtime "$(value RUNTIME_PACKAGE)" "$(value RUNTIME_VERSION)" "$(value RUNTIME_FILE)" "$(value RUNTIME_SHA)"
    fi
    if [ "$ffmpeg_enabled" = true ]; then
        install_pkg ffmpeg "$(value FFMPEG_PACKAGE)" "$(value FFMPEG_VERSION)" "$(value FFMPEG_FILE)" "$(value FFMPEG_SHA)"
    fi
    verify_driver_activation || { state activation_failed "final driver activation check failed"; exit 1; }
    verify_complete_bundle || { state verification_failed "selected SPK bundle or driver activation verification failed"; exit 1; }
    asset_set bundle_sha256 "$bundle_sha" || fail "cannot record verified bundle digest"
    printf 'complete\n' > "$STATE.tmp" && mv -f "$STATE.tmp" "$STATE"
    rm -f "$ROOT/failures"
    log "bundle complete"
}

case "${1:-start}" in
    start) (/bin/sh "$0" run >/dev/null 2>&1 </dev/null &) ;;
    run) run_install ;;
    *) exit 2 ;;
esac
