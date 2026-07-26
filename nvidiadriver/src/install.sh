#!/bin/sh
#
# nvidiadriver - inject a no-auth NVIDIA driver (2-layer package) into DSM.
#
# Runs during the loader build (patches phase, on the TC box where network is
# available). Stages two layers fetched from the GitHub Release into /tmpRoot:
#   kernel    layer -> /tmpRoot/usr/lib/modules/{nvidia,nvidia-uvm,...}.ko
#   userspace layer -> /tmpRoot/usr/local/nvidia/{bin,lib}
# and drops a boot script that modprobes in order + creates device nodes.
#
# Driver VERSION selection (first match wins):
#   1) user_config.json  ."nvidia_driver"   (explicit override, e.g. "535.183.06")
#   2) GPU auto-detect via nvidia-gpu-support.json  (default_branch for the PCI id)
#   3) first driver listed for this platform in nvidia-index.json
#
# No vGPU / license daemon - physical / passthrough GPUs only.

set -o pipefail 2>/dev/null || true

PHASE="${1:-}"
[ "$PHASE" = "patches" ] || [ "$PHASE" = "os_load" ] || exit 0

EXTDIR="$(dirname "$0")"
IDX="$EXTDIR/nvidia-index.json"
SUP="$EXTDIR/nvidia-gpu-support.json"
TMPROOT="${TMPROOT:-/tmpRoot}"
UCONF="/home/tc/user_config.json"

log(){ echo "nvidiadriver: $*" >&2; }
have(){ command -v "$1" >/dev/null 2>&1; }
[ -f "$IDX" ] || { log "no nvidia-index.json, skipping"; exit 0; }
have jq   || { log "jq missing, skipping"; exit 0; }
have curl || { log "curl missing, skipping"; exit 0; }

PLATFORM="$(uname -a | awk '{print $NF}' | cut -d'_' -f2)"
[ -n "$PLATFORM" ] || PLATFORM="$(jq -r '.platforms | keys[0]' "$IDX")"

jq -e ".platforms[\"$PLATFORM\"]" "$IDX" >/dev/null 2>&1 || {
  log "platform $PLATFORM not in index, skipping"; exit 0; }

# --- detect GPU (physical/passthrough) ---------------------------------------
GPUID="$(lspci -nn 2>/dev/null | grep -iE '\[03(00|02)\]' | grep -io '10de:[0-9a-f]\{4\}' | head -1 | tr 'A-Z' 'a-z')"
[ -n "$GPUID" ] && log "detected NVIDIA GPU $GPUID" || log "no NVIDIA GPU detected (will still stage driver)"

# --- resolve driver version --------------------------------------------------
DRV=""
[ -f "$UCONF" ] && DRV="$(jq -r '."nvidia_driver" // empty' "$UCONF" 2>/dev/null)"
if [ -z "$DRV" ] && [ -n "$GPUID" ] && [ -f "$SUP" ]; then
  BRANCH="$(jq -r --arg g "$GPUID" '.gpus[$g].branches[0] // .default_branch' "$SUP" 2>/dev/null)"
  # newest indexed driver whose major branch == $BRANCH
  DRV="$(jq -r --arg p "$PLATFORM" --arg b "$BRANCH" \
      '.platforms[$p].drivers | keys | map(select(startswith($b+"."))) | sort | reverse | .[0] // empty' "$IDX")"
  [ -n "$DRV" ] && log "auto-selected driver $DRV (branch $BRANCH for $GPUID)"
fi
[ -z "$DRV" ] && DRV="$(jq -r --arg p "$PLATFORM" '.platforms[$p].drivers | keys | sort | reverse | .[0]' "$IDX")"
[ -z "$DRV" ] || [ "$DRV" = "null" ] && { log "no driver resolved, skipping"; exit 0; }

# compatibility guard
if [ -n "$GPUID" ] && [ -f "$SUP" ]; then
  OKB="$(echo "$DRV" | cut -d. -f1)"
  if jq -e --arg g "$GPUID" '.gpus[$g]' "$SUP" >/dev/null 2>&1; then
    jq -e --arg g "$GPUID" --arg b "$OKB" '.gpus[$g].branches | index($b)' "$SUP" >/dev/null 2>&1 \
      || log "WARN: branch $OKB not listed compatible with $GPUID - proceeding as requested"
  fi
fi
log "installing NVIDIA driver $DRV for $PLATFORM"

# --- fetch the two layers ----------------------------------------------------
BASE="$(jq -r '.release_base' "$IDX")"
KOF="$(jq -r --arg p "$PLATFORM" --arg d "$DRV" '.platforms[$p].drivers[$d].ko.file' "$IDX")"
USF="$(jq -r --arg p "$PLATFORM" --arg d "$DRV" '.platforms[$p].drivers[$d].userspace.file' "$IDX")"
KOSHA="$(jq -r --arg p "$PLATFORM" --arg d "$DRV" '.platforms[$p].drivers[$d].ko.sha256' "$IDX")"
USSHA="$(jq -r --arg p "$PLATFORM" --arg d "$DRV" '.platforms[$p].drivers[$d].userspace.sha256' "$IDX")"
DL=/tmp/nvdriver; mkdir -p "$DL"

fetch(){ # url dest sha
  curl -kL# "$1" -o "$2" || { log "download failed: $1"; return 1; }
  case "$3" in TBD*|""|null) ;; *)
    a="$(sha256sum "$2" | cut -d' ' -f1)"
    [ "$a" = "$3" ] || { log "sha256 mismatch for $2 (want $3 got $a)"; return 1; } ;;
  esac
}
fetch "$BASE/$KOF" "$DL/$KOF" "$KOSHA" || exit 0
fetch "$BASE/$USF" "$DL/$USF" "$USSHA" || exit 0

# --- inject kernel layer -----------------------------------------------------
KMODDIR="$TMPROOT/usr/lib/modules"
mkdir -p "$KMODDIR"
tar -xzf "$DL/$KOF" -C /tmp/nvidia-ko-x 2>/dev/null || { mkdir -p /tmp/nvidia-ko-x && tar -xzf "$DL/$KOF" -C /tmp/nvidia-ko-x; }
for ko in /tmp/nvidia-ko-x/*.ko; do
  [ -f "$ko" ] || continue
  cp -f "$ko" "$KMODDIR/$(basename "$ko")"
  log "  staged $(basename "$ko")"
done

# --- inject userspace layer --------------------------------------------------
USDIR="$TMPROOT/usr/local/nvidia"
mkdir -p "$USDIR"
tar -xzf "$DL/$USF" -C "$USDIR"
# recreate sonames (libnvidia-ml.so.1 -> .so.<ver>, libcuda.so.1, ...)
( cd "$USDIR/lib" 2>/dev/null && for f in *.so."$DRV"; do
    [ -f "$f" ] || continue
    base="${f%.so.$DRV}.so"; ln -sf "$f" "$base.1"; ln -sf "$base.1" "$base"
  done ) 2>/dev/null || true
# Expose the sonames on the default loader path. DSM has no /etc/ld.so.conf.d and
# ldconfig does NOT reliably honor /etc/ld.so.conf, so symlink the libs straight
# into /usr/lib - verified on-box that Plex/jellyfin-ffmpeg then resolve
# libnvidia-encode/libnvcuvid/libcuda WITHOUT LD_LIBRARY_PATH. (Also redone at
# boot in rc.d/nvidia.sh, since /usr/lib is rebuilt from the pat each boot.)
mkdir -p "$TMPROOT/usr/lib"
( cd "$USDIR/lib" 2>/dev/null && for so in *.so*; do
    [ -e "$so" ] && ln -sf "/usr/local/nvidia/lib/$so" "$TMPROOT/usr/lib/$so"
  done ) 2>/dev/null || true

# --- boot script: load order + device nodes ----------------------------------
RCD="$TMPROOT/usr/local/etc/rc.d"; mkdir -p "$RCD"
cat > "$RCD/nvidia.sh" <<'RC'
#!/bin/sh
# nvidiadriver boot hook - load modules in dependency order, create nodes.
# nvidia + nvidia-uvm are the compute core (nvidia-smi/CUDA). nvidia-modeset and
# nvidia-drm are display-only and are best-effort: DSM kernels ship no
# backlight.ko, so modeset may fail with 'Unknown symbol backlight_device_*' -
# that is expected and does NOT affect compute. Failures are ignored.
case "$1" in start|"")
  for m in nvidia nvidia-uvm nvidia-modeset nvidia-drm; do
    [ -f "/usr/lib/modules/$m.ko" ] && /sbin/insmod "/usr/lib/modules/$m.ko" 2>/dev/null
  done
  # device nodes (nvidia-modprobe normally does this; do it explicitly)
  major=$(awk '$2=="nvidia-frontend"||$2=="nvidia"{print $1}' /proc/devices | head -1)
  [ -n "$major" ] && {
    [ -e /dev/nvidiactl ] || mknod -m 666 /dev/nvidiactl c "$major" 255
    n=0; while [ $n -lt 8 ]; do [ -e /dev/nvidia$n ] || mknod -m 666 /dev/nvidia$n c "$major" $n; n=$((n+1)); done
  }
  umajor=$(awk '$2=="nvidia-uvm"{print $1}' /proc/devices | head -1)
  [ -n "$umajor" ] && { [ -e /dev/nvidia-uvm ] || mknod -m 666 /dev/nvidia-uvm c "$umajor" 0; }
  # expose libs on the default loader path so Plex/Jellyfin/ffmpeg resolve
  # libnvidia-encode/libnvcuvid/libcuda without LD_LIBRARY_PATH. DSM lacks
  # /etc/ld.so.conf.d and rebuilds /usr/lib each boot, so (re)symlink here.
  for so in /usr/local/nvidia/lib/*.so*; do
    [ -e "$so" ] && ln -sf "$so" "/usr/lib/$(basename "$so")"
  done
  [ -x /sbin/ldconfig ] && /sbin/ldconfig 2>/dev/null
  export PATH="/usr/local/nvidia/bin:$PATH"
  ;;
esac
RC
chmod +x "$RCD/nvidia.sh"

# ld path for the userspace libs
LDC="$TMPROOT/etc/ld.so.conf.d"; mkdir -p "$LDC"
echo "/usr/local/nvidia/lib" > "$LDC/nvidia.conf"

log "done - driver $DRV staged into $TMPROOT (loads at DSM boot via rc.d/nvidia.sh)"
exit 0
