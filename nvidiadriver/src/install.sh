#!/bin/sh
#
# nvidiadriver - inject a no-auth NVIDIA driver (2-layer package) into DSM.
#
# TWO explicitly-separated redpill phases (see the case dispatcher at the end):
#
#   patches : the network IS available here. Download every layer (kernel +
#             userspace [+ optional ffmpeg]) into a cache (/tmp/nvdriver).
#             /tmpRoot does not exist yet, so NOTHING is injected in this phase.
#
#   os_load : /tmpRoot (the DSM rootfs) is mounted, but the network may be down.
#             Copy/extract the pre-downloaded layers from the cache into /tmpRoot
#             and wire up the boot hook. Only if the cache is missing does it
#             fall back to downloading here.
#
# Version selection (both phases, deterministic): /addons/nvidia.conf (baked by
# functions.sh from the menu choice) -> GPU auto-detect via nvidia-gpu-support
# -> newest for the platform. No vGPU / license daemon - physical/passthrough only.

CACHE=/tmp/nvdriver          # survives patches -> os_load (same junior tmpfs)
LOGF=""                      # persistent log; set at os_load once /tmpRoot exists

# log to stderr (serial console) AND, once LOGF is set, to a file that persists
# into the booted DSM as /var/log/nvidiadriver.log
log(){ echo "nvidiadriver: $*" >&2; [ -n "$LOGF" ] && echo "$(date '+%H:%M:%S') nvidiadriver: $*" >> "$LOGF" 2>/dev/null; }

# jq/curl exist in junior but PATH is minimal and BusyBox ash has no 'command'
# builtin -> use 'type', then search common dirs and prepend to PATH.
ensure_bin(){
  type "$1" >/dev/null 2>&1 && return 0
  for c in /usr/bin /bin /usr/local/bin /opt/bin /sbin /usr/sbin \
           /tmpRoot/usr/bin /tmpRoot/bin /tmpRoot/usr/local/bin /exts/misc; do
    [ -x "$c/$1" ] && { export PATH="$c:$PATH"; return 0; }
  done
  return 1
}

# a sha256 tool if any. Only JUNIOR-native binaries - NOT the DSM ones under
# /tmpRoot, which need DSM libs (libcrypto.so.3) absent from junior's loader path
# and therefore fail at runtime. Junior/BusyBox usually has none -> verify skipped.
SHA256=""
find_sha(){
  for c in sha256sum /usr/bin/sha256sum /sbin/sha256sum /bin/sha256sum; do
    case "$c" in /*) [ -x "$c" ] && { SHA256="$c"; return; } ;;
                 *)  type "$c" >/dev/null 2>&1 && { SHA256="$c"; return; } ;; esac
  done
}

fetch(){ # url dest sha
  curl -kL# "$1" -o "$2" || { log "download failed: $1"; return 1; }
  [ -s "$2" ] || { log "empty download: $1"; return 1; }
  case "$3" in TBD*|""|null) return 0 ;; esac
  if [ -n "$SHA256" ]; then
    a="$($SHA256 "$2" 2>/dev/null | cut -d' ' -f1)"
    if [ -z "$a" ]; then
      log "sha tool produced no output ($SHA256 unusable) - skipping verify for $(basename "$2")"
    elif [ "$a" != "$3" ]; then
      log "sha256 mismatch for $2 (want $3 got $a)"; return 1
    fi
  else
    log "no sha256 tool here - skipping checksum verify for $(basename "$2")"
  fi
}

# --- shared: locate ext files/tools, platform, GPU, resolve driver + files ---
# Sets: IDX SUP PLATFORM GPUID DRV WANT_FF BASE KOF USF FFF KOSHA USSHA FFFSHA
init_common(){
  EXTDIR=/exts/nvidiadriver                       # redpill lays ext files here
  [ -f "$EXTDIR/nvidia-index.json" ] || EXTDIR="$(dirname "$0")"
  IDX="$EXTDIR/nvidia-index.json"
  SUP="$EXTDIR/nvidia-gpu-support.json"
  [ -f "$IDX" ] || { log "no nvidia-index.json, skipping"; return 1; }
  ensure_bin jq   || { log "jq not found, skipping"; return 1; }
  ensure_bin curl || { log "curl not found, skipping"; return 1; }
  find_sha

  # menu choice baked into /addons/nvidia.conf (junior can't read user_config.json)
  [ -f /addons/nvidia.conf ] && . /addons/nvidia.conf 2>/dev/null

  PLATFORM="$(uname -a | awk '{print $NF}' | cut -d'_' -f2)"
  [ -n "$PLATFORM" ] || PLATFORM="$(jq -r '.platforms | keys[0]' "$IDX")"
  jq -e ".platforms[\"$PLATFORM\"]" "$IDX" >/dev/null 2>&1 || { log "platform $PLATFORM not in index, skipping"; return 1; }

  # detect NVIDIA GPU (lspci, sysfs fallback for junior)
  GPUID="$(lspci -nn 2>/dev/null | grep -iE '\[03(00|02)\]' | grep -io '10de:[0-9a-f]\{4\}' | head -1 | tr 'A-Z' 'a-z')"
  if [ -z "$GPUID" ]; then
    for d in /sys/bus/pci/devices/*; do
      [ "$(cat "$d/vendor" 2>/dev/null)" = "0x10de" ] || continue
      case "$(cat "$d/class" 2>/dev/null)" in 0x0300*|0x0302*)
        GPUID="10de:$(sed 's/^0x//' "$d/device" 2>/dev/null)"; break ;; esac
    done
  fi
  [ -n "$GPUID" ] && log "detected NVIDIA GPU $GPUID" || log "no NVIDIA GPU detected"

  # resolve version: /addons override -> GPU branch (GSP-aware) -> newest.
  # GSP-aware: a GPU's branches[] is newest-preferred (usually 580 first), but
  # 580 on a needs_gsp GPU with NO available firmware blob (currently Ada/RTX 40,
  # Blackwell/RTX 50 - NVIDIA's .run only bundles gsp_tu10x.bin/gsp_ga10x.bin)
  # would install a driver that loads but fails to initialise. The interactive
  # standalone installer catches this with a confirm prompt; this addon runs
  # unattended at boot, so it must skip such a branch on its own and fall
  # through to the GPU's next candidate (e.g. 550) instead of silently
  # installing something broken.
  DRV="${nvidia_driver:-}"
  if [ -z "$DRV" ] && [ -n "$GPUID" ] && [ -f "$SUP" ]; then
    NEEDS_GSP="$(jq -r --arg g "$GPUID" '.gpus[$g].needs_gsp // false' "$SUP" 2>/dev/null)"
    GSP_FW="$(jq -r --arg g "$GPUID" '.gpus[$g].gsp_fw // empty' "$SUP" 2>/dev/null)"
    for BRANCH in $(jq -r --arg g "$GPUID" '.gpus[$g].branches[]? // empty' "$SUP" 2>/dev/null); do
      CAND="$(jq -r --arg p "$PLATFORM" --arg b "$BRANCH" '.platforms[$p].drivers | keys | map(select(startswith($b+"."))) | sort | reverse | .[0] // empty' "$IDX")"
      { [ -n "$CAND" ] && [ "$CAND" != "null" ]; } || continue
      if [ "$BRANCH" = "580" ] && [ "$NEEDS_GSP" = "true" ]; then
        if [ -z "$GSP_FW" ] || [ "$GSP_FW" = "null" ]; then
          log "GPU $GPUID needs GSP firmware but none is bundled for it - skipping 580"; continue
        fi
        AVAIL="$(jq -r --arg d "$CAND" --arg f "$GSP_FW" '.gsp_firmware[$d].chips // [] | index($f) // empty' "$IDX" 2>/dev/null)"
        [ -n "$AVAIL" ] || { log "GPU $GPUID needs GSP firmware ($GSP_FW) but $CAND's index has none - skipping 580"; continue; }
      fi
      DRV="$CAND"; break
    done
  fi
  [ -z "$DRV" ] && DRV="$(jq -r --arg p "$PLATFORM" '.platforms[$p].drivers | keys | sort | reverse | .[0]' "$IDX")"
  { [ -z "$DRV" ] || [ "$DRV" = "null" ]; } && { log "no driver resolved, skipping"; return 1; }
  WANT_FF="${nvidia_ffmpeg:-false}"

  BASE="$(jq -r '.release_base' "$IDX")"
  KOF="$(jq   -r --arg p "$PLATFORM" --arg d "$DRV" '.platforms[$p].drivers[$d].ko.file' "$IDX")"
  USF="$(jq   -r --arg p "$PLATFORM" --arg d "$DRV" '.platforms[$p].drivers[$d].userspace.file' "$IDX")"
  FFF="$(jq   -r --arg p "$PLATFORM" --arg d "$DRV" '.platforms[$p].drivers[$d].ffmpeg.file // empty' "$IDX")"
  KOSHA="$(jq -r --arg p "$PLATFORM" --arg d "$DRV" '.platforms[$p].drivers[$d].ko.sha256' "$IDX")"
  USSHA="$(jq -r --arg p "$PLATFORM" --arg d "$DRV" '.platforms[$p].drivers[$d].userspace.sha256' "$IDX")"
  FFFSHA="$(jq -r --arg p "$PLATFORM" --arg d "$DRV" '.platforms[$p].drivers[$d].ffmpeg.sha256 // empty' "$IDX")"

  # GSP firmware (Turing/Ampere-GA10x only for now; see comment above). GSP_FW
  # may already be set from the loop above; re-derive it here too so the
  # `nvidia_driver` override path (which skips that loop) still gets it.
  [ -n "${GSP_FW:-}" ] || GSP_FW="$(jq -r --arg g "$GPUID" '.gpus[$g].gsp_fw // empty' "$SUP" 2>/dev/null)"
  GFF=""; GFSHA=""
  if [ -n "$GSP_FW" ] && [ "$GSP_FW" != "null" ]; then
    AVAIL="$(jq -r --arg d "$DRV" --arg f "$GSP_FW" '.gsp_firmware[$d].chips // [] | index($f) // empty' "$IDX" 2>/dev/null)"
    if [ -n "$AVAIL" ]; then
      GFF="$(jq -r --arg d "$DRV" '.gsp_firmware[$d].file' "$IDX")"
      GFSHA="$(jq -r --arg d "$DRV" '.gsp_firmware[$d].sha256' "$IDX")"
    fi
  fi
  return 0
}

###############################################################################
# PHASE 1 - on_patches : download every layer to the cache (network available)
###############################################################################
do_download(){
  mkdir -p "$CACHE"
  echo "$DRV" > "$CACHE/selected"    # lock the version so os_load injects the same one
  log "pre-downloading driver $DRV for $PLATFORM -> $CACHE (patches phase)"
  fetch "$BASE/$KOF" "$CACHE/$KOF" "$KOSHA" || return 1
  fetch "$BASE/$USF" "$CACHE/$USF" "$USSHA" || return 1
  if [ "$WANT_FF" = "true" ] && [ -n "$FFF" ]; then
    fetch "$BASE/$FFF" "$CACHE/$FFF" "$FFFSHA" || log "ffmpeg layer download failed (optional)"
  fi
  if [ -n "$GFF" ]; then
    fetch "$BASE/$GFF" "$CACHE/$GFF" "$GFSHA" || log "GSP firmware download failed (GPU needs it - modeset/uvm may not init)"
  fi
  log "pre-download complete: $(ls "$CACHE" 2>/dev/null | tr '\n' ' ')"
}

###############################################################################
# PHASE 2 - on_os_load : inject the cached layers into the mounted /tmpRoot
###############################################################################
do_inject(){
  TR="${TMPROOT:-/tmpRoot}"
  [ -d "$TR/usr" ] || { echo "nvidiadriver: $TR not mounted (late) - abort" >&2; return 1; }
  LOGF="$TR/var/log/nvidiadriver.log"
  mkdir -p "$TR/var/log" 2>/dev/null; echo "===== nvidiadriver os_load $(date) =====" >> "$LOGF" 2>/dev/null

  # Use the EXACT version the patches phase downloaded (the GPU may not be
  # enumerable at os_load, so re-resolving here could pick a different one).
  if [ -f "$CACHE/selected" ]; then
    DRV="$(cat "$CACHE/selected")"
    KOF="$(jq -r --arg p "$PLATFORM" --arg d "$DRV" '.platforms[$p].drivers[$d].ko.file' "$IDX")"
    USF="$(jq -r --arg p "$PLATFORM" --arg d "$DRV" '.platforms[$p].drivers[$d].userspace.file' "$IDX")"
    FFF="$(jq -r --arg p "$PLATFORM" --arg d "$DRV" '.platforms[$p].drivers[$d].ffmpeg.file // empty' "$IDX")"
    GFF=""
    if [ -n "${GSP_FW:-}" ] && [ "$GSP_FW" != "null" ]; then
      AVAIL="$(jq -r --arg d "$DRV" --arg f "$GSP_FW" '.gsp_firmware[$d].chips // [] | index($f) // empty' "$IDX" 2>/dev/null)"
      [ -n "$AVAIL" ] && GFF="$(jq -r --arg d "$DRV" '.gsp_firmware[$d].file' "$IDX")"
    fi
    log "using pre-downloaded driver $DRV (locked at patches phase)"
  fi

  # normally the patches phase already cached the layers; fall back to a
  # download here only if they are missing (network may or may not be up).
  if [ ! -s "$CACHE/$KOF" ] || [ ! -s "$CACHE/$USF" ]; then
    log "cache missing - trying download at os_load (network may be down)"
    do_download || { log "no cached layers and download failed - aborting"; return 1; }
  fi
  log "injecting driver $DRV into $TR"

  # --- kernel layer -> /tmpRoot/usr/lib/modules ---
  KMODDIR="$TR/usr/lib/modules"; mkdir -p "$KMODDIR"
  rm -rf /tmp/nv-ko-x; mkdir -p /tmp/nv-ko-x; tar -xzf "$CACHE/$KOF" -C /tmp/nv-ko-x
  for ko in /tmp/nv-ko-x/*.ko; do
    [ -f "$ko" ] && { cp -f "$ko" "$KMODDIR/$(basename "$ko")"; log "  staged $(basename "$ko")"; }
  done
  # Platform marker for the boot hook's mismatch guard (see rc.d/nvidia.sh
  # below) - all kver5 platforms share the exact same vermagic string, so the
  # kernel's own check can't catch a leftover .ko from a previously-selected
  # platform (e.g. after switching the loader's declared platform).
  echo "$PLATFORM" > "$KMODDIR/.nvidia-platform"

  # --- GSP firmware -> /tmpRoot/lib/firmware/nvidia/<driver_ver>/ (must exist
  # before nvidia.ko loads - request_firmware() is called at probe time) ---
  if [ -n "$GFF" ] && [ -s "$CACHE/$GFF" ]; then
    FWDIR="$TR/lib/firmware/nvidia/$DRV"; mkdir -p "$FWDIR"
    rm -rf /tmp/nv-gsp-x; mkdir -p /tmp/nv-gsp-x; tar -xzf "$CACHE/$GFF" -C /tmp/nv-gsp-x firmware 2>/dev/null
    if [ -f "/tmp/nv-gsp-x/firmware/$GSP_FW" ]; then
      cp -f "/tmp/nv-gsp-x/firmware/$GSP_FW" "$FWDIR/$GSP_FW"
      log "  staged GSP firmware $GSP_FW -> /lib/firmware/nvidia/$DRV/"
    fi
  fi

  # --- userspace layer -> /tmpRoot/usr/local/nvidia ---
  USDIR="$TR/usr/local/nvidia"; mkdir -p "$USDIR"
  tar -xzf "$CACHE/$USF" -C "$USDIR"
  ( cd "$USDIR/lib" 2>/dev/null && for f in *.so."$DRV"; do
      [ -f "$f" ] || continue; base="${f%.so.$DRV}.so"; ln -sf "$f" "$base.1"; ln -sf "$base.1" "$base"
    done ) 2>/dev/null || true
  # expose libs on the default loader path (DSM lacks ld.so.conf.d; rc.d redoes
  # this each boot since /usr/lib is rebuilt from the pat)
  mkdir -p "$TR/usr/lib"
  ( cd "$USDIR/lib" 2>/dev/null && for so in *.so*; do
      [ -e "$so" ] && ln -sf "/usr/local/nvidia/lib/$so" "$TR/usr/lib/$so"
    done ) 2>/dev/null || true

  # nvidia-smi: a REAL binary copy, not just a PATH export. nvidia-container-cli
  # discovers /usr/bin/nvidia-smi by path and bind-mounts that exact file into
  # containers, where /usr/local/nvidia doesn't exist - a PATH-only fix (what
  # the boot hook used to do) leaves that binary broken inside containers.
  mkdir -p "$TR/usr/bin"
  [ -f "$USDIR/bin/nvidia-smi" ] && { cp -f "$USDIR/bin/nvidia-smi" "$TR/usr/bin/nvidia-smi"; chmod +x "$TR/usr/bin/nvidia-smi"; }

  # --- optional NVENC ffmpeg layer (SynoCommunity Jellyfin pkg / CLI) ---
  if [ "$WANT_FF" = "true" ] && [ -s "$CACHE/$FFF" ]; then
    mkdir -p "$USDIR/bin"; tar -xzf "$CACHE/$FFF" -C "$USDIR"
    chmod +x "$USDIR/bin/ffmpeg" "$USDIR/bin/ffprobe" 2>/dev/null
    log "ffmpeg staged -> /usr/local/nvidia/bin/ffmpeg (point Jellyfin 'FFmpeg path' here)"
  fi

  # --- boot hook: load modules + create nodes + expose libs at DSM boot ---
  RCD="$TR/usr/local/etc/rc.d"; mkdir -p "$RCD"
  cat > "$RCD/nvidia.sh" <<'RC'
#!/bin/sh
# nvidiadriver boot hook - load modules in dependency order, create nodes.
# nvidia + nvidia-uvm are the compute core (nvidia-smi/CUDA) and load on every
# platform. nvidia-modeset/nvidia-drm are display-only and best-effort: on
# headless platforms (no backlight.ko in that platform's DSM kernel) modeset
# fails to load with 'Unknown symbol backlight_device_*' - harmless, expected,
# irrelevant to compute/NVENC. On platforms with real backlight/display
# support (e.g. geminilakenk) it loads fine - confirmed on real hardware.
RCLOG=/var/log/nvidiadriver.log
rclog(){ echo "$(date '+%H:%M:%S') rc.d/nvidia: $*" >> "$RCLOG" 2>/dev/null; }
case "$1" in start|"")
  rclog "=== boot hook start ==="
  # Platform guard: skip if the installed .ko were built for a different
  # platform than the one currently running. vermagic alone can't catch this
  # (identical text across kver5 platforms) and per-platform kernel .config
  # can genuinely differ (e.g. backlight/acpi_video on/off).
  CURP="$(uname -a | awk '{print $NF}' | cut -d'_' -f2)"
  STOREDP="$(cat /usr/lib/modules/.nvidia-platform 2>/dev/null)"
  if [ -n "$STOREDP" ] && [ "$STOREDP" != "$CURP" ]; then
    rclog "SKIPPED: installed .ko are for platform '$STOREDP' but running on '$CURP' - re-select the driver for this platform"
    exit 0
  fi
  for m in nvidia nvidia-uvm nvidia-modeset nvidia-drm; do
    if [ -f "/usr/lib/modules/$m.ko" ]; then
      if /sbin/insmod "/usr/lib/modules/$m.ko" 2>>"$RCLOG"; then rclog "insmod $m OK"; else rclog "insmod $m FAILED (see above)"; fi
    fi
  done
  # nodes for the ACTUAL number of GPUs only (the driver usually makes these via
  # devtmpfs already; do NOT create phantom nvidia1..7 for GPUs that don't exist)
  major=$(awk '$2=="nvidia-frontend"||$2=="nvidia"{print $1}' /proc/devices | head -1)
  ngpu=$(ls -d /proc/driver/nvidia/gpus/* 2>/dev/null | wc -l); [ "$ngpu" -ge 1 ] || ngpu=1
  [ -n "$major" ] && {
    [ -e /dev/nvidiactl ] || mknod -m 666 /dev/nvidiactl c "$major" 255
    n=0; while [ "$n" -lt "$ngpu" ]; do [ -e /dev/nvidia$n ] || mknod -m 666 /dev/nvidia$n c "$major" $n; n=$((n+1)); done
  }
  umajor=$(awk '$2=="nvidia-uvm"{print $1}' /proc/devices | head -1)
  [ -n "$umajor" ] && { [ -e /dev/nvidia-uvm ] || mknod -m 666 /dev/nvidia-uvm c "$umajor" 0; }
  # /dev/nvidia-modeset: unlike nvidia-uvm-tools and /dev/dri/* (auto-created
  # by DSM's udev once the module registers), this one needs an explicit
  # create - confirmed on real hardware. Use NVIDIA's own bundled tool rather
  # than hardcoding the minor (254 by convention). No-ops harmlessly if
  # nvidia-modeset.ko didn't load (e.g. headless platform, no backlight.ko).
  [ -e /dev/nvidia-modeset ] || /usr/local/nvidia/bin/nvidia-modprobe -m 2>/dev/null
  for so in /usr/local/nvidia/lib/*.so*; do
    [ -e "$so" ] && ln -sf "$so" "/usr/lib/$(basename "$so")"
  done
  [ -x /sbin/ldconfig ] && /sbin/ldconfig 2>/dev/null
  export PATH="/usr/local/nvidia/bin:$PATH"
  rclog "loaded: $(lsmod 2>/dev/null | grep -c '^nvidia') nvidia modules; nodes: $(ls /dev/nvidia* 2>/dev/null | tr '\n' ' ')"
  rclog "=== boot hook done (run 'nvidia-smi' to verify) ==="
  ;;
esac
RC
  chmod +x "$RCD/nvidia.sh"
  mkdir -p "$TR/etc/ld.so.conf.d"; echo "/usr/local/nvidia/lib" > "$TR/etc/ld.so.conf.d/nvidia.conf"
  log "done - driver $DRV injected into $TR (loads at DSM boot via rc.d/nvidia.sh)"
}

###############################################################################
# dispatcher - keep the two events strictly separated
###############################################################################
# NOTE on the arg: redpill's LKM passes an internal STAGE name, not the hook
# name. The on_patches hook runs the script with "patches"; the on_os_load hook
# runs it with "late" (same as the disks addon's install-new.sh 'late)' case,
# which is what does the /tmpRoot work).
case "$1" in
  patches)  init_common && do_download ;;   # download only (internet OK, no /tmpRoot)
  late)     init_common && do_inject   ;;   # inject cached layers into /tmpRoot
  *)        echo "nvidiadriver: usage: $0 {patches|late}" >&2 ;;
esac
exit 0
