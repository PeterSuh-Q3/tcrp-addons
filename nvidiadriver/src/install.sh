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

# a sha256 tool if any (junior/BusyBox often has none -> verify is skipped)
SHA256=""
find_sha(){
  for c in sha256sum /usr/bin/sha256sum /sbin/sha256sum /bin/sha256sum /tmpRoot/usr/bin/sha256sum; do
    case "$c" in /*) [ -x "$c" ] && { SHA256="$c"; return; } ;;
                 *)  type "$c" >/dev/null 2>&1 && { SHA256="$c"; return; } ;; esac
  done
}

fetch(){ # url dest sha
  curl -kL# "$1" -o "$2" || { log "download failed: $1"; return 1; }
  [ -s "$2" ] || { log "empty download: $1"; return 1; }
  case "$3" in TBD*|""|null) return 0 ;; esac
  if [ -n "$SHA256" ]; then
    a="$($SHA256 "$2" | cut -d' ' -f1)"
    [ "$a" = "$3" ] || { log "sha256 mismatch for $2 (want $3 got $a)"; return 1; }
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

  # resolve version: /addons override -> GPU branch -> newest
  DRV="${nvidia_driver:-}"
  if [ -z "$DRV" ] && [ -n "$GPUID" ] && [ -f "$SUP" ]; then
    BRANCH="$(jq -r --arg g "$GPUID" '.gpus[$g].branches[0] // .default_branch' "$SUP" 2>/dev/null)"
    DRV="$(jq -r --arg p "$PLATFORM" --arg b "$BRANCH" '.platforms[$p].drivers | keys | map(select(startswith($b+"."))) | sort | reverse | .[0] // empty' "$IDX")"
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
  return 0
}

###############################################################################
# PHASE 1 - on_patches : download every layer to the cache (network available)
###############################################################################
do_download(){
  mkdir -p "$CACHE"
  log "pre-downloading driver $DRV for $PLATFORM -> $CACHE (patches phase)"
  fetch "$BASE/$KOF" "$CACHE/$KOF" "$KOSHA" || return 1
  fetch "$BASE/$USF" "$CACHE/$USF" "$USSHA" || return 1
  if [ "$WANT_FF" = "true" ] && [ -n "$FFF" ]; then
    fetch "$BASE/$FFF" "$CACHE/$FFF" "$FFFSHA" || log "ffmpeg layer download failed (optional)"
  fi
  log "pre-download complete: $(ls "$CACHE" 2>/dev/null | tr '\n' ' ')"
}

###############################################################################
# PHASE 2 - on_os_load : inject the cached layers into the mounted /tmpRoot
###############################################################################
do_inject(){
  TR="${TMPROOT:-/tmpRoot}"
  [ -d "$TR/usr" ] || { echo "nvidiadriver: $TR not mounted (os_load) - abort" >&2; return 1; }
  LOGF="$TR/var/log/nvidiadriver.log"
  mkdir -p "$TR/var/log" 2>/dev/null; echo "===== nvidiadriver os_load $(date) =====" >> "$LOGF" 2>/dev/null

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
# nvidia + nvidia-uvm are the compute core (nvidia-smi/CUDA). nvidia-modeset and
# nvidia-drm are display-only and best-effort: DSM ships no backlight.ko so
# modeset may fail with 'Unknown symbol backlight_device_*' - expected, ignored.
RCLOG=/var/log/nvidiadriver.log
rclog(){ echo "$(date '+%H:%M:%S') rc.d/nvidia: $*" >> "$RCLOG" 2>/dev/null; }
case "$1" in start|"")
  rclog "=== boot hook start ==="
  for m in nvidia nvidia-uvm nvidia-modeset nvidia-drm; do
    if [ -f "/usr/lib/modules/$m.ko" ]; then
      if /sbin/insmod "/usr/lib/modules/$m.ko" 2>>"$RCLOG"; then rclog "insmod $m OK"; else rclog "insmod $m FAILED (see above)"; fi
    fi
  done
  major=$(awk '$2=="nvidia-frontend"||$2=="nvidia"{print $1}' /proc/devices | head -1)
  [ -n "$major" ] && {
    [ -e /dev/nvidiactl ] || mknod -m 666 /dev/nvidiactl c "$major" 255
    n=0; while [ $n -lt 8 ]; do [ -e /dev/nvidia$n ] || mknod -m 666 /dev/nvidia$n c "$major" $n; n=$((n+1)); done
  }
  umajor=$(awk '$2=="nvidia-uvm"{print $1}' /proc/devices | head -1)
  [ -n "$umajor" ] && { [ -e /dev/nvidia-uvm ] || mknod -m 666 /dev/nvidia-uvm c "$umajor" 0; }
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
case "$1" in
  patches)  init_common && do_download ;;   # download only (internet OK, no /tmpRoot)
  os_load)  init_common && do_inject   ;;   # inject cached layers into /tmpRoot
  *)        echo "nvidiadriver: usage: $0 {patches|os_load}" >&2 ;;
esac
exit 0
