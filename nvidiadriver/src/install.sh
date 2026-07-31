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

  # The platform NAME alone does not identify the kernel ABI. The same platform
  # ships different kernels across DSM releases (broadwell & friends are
  # 4.4.180 on DSM 7.0/7.1 but 4.4.302 on 7.2+), and module vermagic embeds the
  # exact version, so insmod rejects a mismatch. Junior already runs the real
  # DSM kernel - that is why the uname-based PLATFORM detection above works -
  # so uname -r is authoritative here too.
  # Platforms present on several kernels carry a 'kernels' map keyed by
  # version; single-kernel ones keep the flat 'drivers' plus a 'kver'.
  KVER="$(uname -r | sed 's/[^0-9.].*$//')"
  if jq -e --arg p "$PLATFORM" '.platforms[$p].kernels' "$IDX" >/dev/null 2>&1; then
    jq -e --arg p "$PLATFORM" --arg k "$KVER" '.platforms[$p].kernels[$k]' "$IDX" >/dev/null 2>&1 || {
      log "platform $PLATFORM has no modules for kernel $KVER (published: $(jq -r --arg p "$PLATFORM" '.platforms[$p].kernels|keys|join(",")' "$IDX")), skipping"; return 1; }
  else
    IKVER="$(jq -r --arg p "$PLATFORM" '.platforms[$p].kver // empty' "$IDX")"
    if [ -n "$IKVER" ] && [ "$IKVER" != "$KVER" ]; then
      log "platform $PLATFORM modules are built for kernel $IKVER but this box runs $KVER - skipping (vermagic would be rejected)"; return 1
    fi
  fi
  log "platform $PLATFORM, kernel $KVER"
  # Resolved drivers node - per-kernel entry when present, flat otherwise.
  DQ='(.platforms[$p].kernels[$k].drivers // .platforms[$p].drivers)'

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

  # --- resolve the driver version -------------------------------------------
  # Mirrors the standalone installer's logic, minus the prompts: this runs
  # unattended at boot, so every judgement it would ask about has to be decided
  # here and explained in the log.
  #
  # AVAIL = the branches actually indexed for THIS platform+kernel. Everything
  # below intersects with it, so it is structurally impossible to select a
  # driver we do not publish (kver4 platforms only have 550, kver5 have all four).
  AVAIL="$(jq -r --arg p "$PLATFORM" --arg k "$KVER" "$DQ"' | keys | map(.[0:3]) | unique | join(" ")' "$IDX")"
  has_branch(){ case " $AVAIL " in *" $1 "*) return 0 ;; esac; return 1; }
  log "branches published for $PLATFORM/$KVER: ${AVAIL:-none}"

  GKNOWN=false; GBRANCHES=""; GLEGACY=""
  if [ -n "$GPUID" ] && [ -f "$SUP" ] && jq -e --arg g "$GPUID" '.gpus[$g]' "$SUP" >/dev/null 2>&1; then
    GKNOWN=true
    GBRANCHES="$(jq -r --arg g "$GPUID" '.gpus[$g].branches // [] | join(" ")' "$SUP" 2>/dev/null)"
    GLEGACY="$(jq -r --arg g "$GPUID" '.gpus[$g].legacy_driver // ""' "$SUP" 2>/dev/null)"
  fi
  NEEDS_GSP="$(jq -r --arg g "$GPUID" '.gpus[$g].needs_gsp // false' "$SUP" 2>/dev/null)"
  GSP_FW="$(jq -r --arg g "$GPUID" '.gpus[$g].gsp_fw // empty' "$SUP" 2>/dev/null)"

  DRV="${nvidia_driver:-}"
  if [ -z "$DRV" ]; then
    # A GPU that NVIDIA only supports through a legacy branch (390.xx and older)
    # cannot be driven by anything this project builds. Installing anyway would
    # download ~300MB and inject modules that load and then bind to no device -
    # skip and say why instead.
    if [ -n "$GLEGACY" ] && [ "$GLEGACY" != "null" ]; then
      log "GPU $GPUID is only supported by NVIDIA's $GLEGACY legacy driver, which this project does not build - skipping"
      return 1
    fi
    # Newest branch the GPU supports that we also publish here. branches[] is
    # newest-preferred. 580 uses the open kernel module, which on Turing+
    # refuses to initialise without a GSP blob; we only ship the blobs NVIDIA's
    # .run bundles (Turing + consumer Ampere), so for Ada/Blackwell/GA100 580 is
    # present but unusable and must be passed over.
    for BRANCH in $GBRANCHES; do
      has_branch "$BRANCH" || continue
      CAND="$(jq -r --arg p "$PLATFORM" --arg k "$KVER" --arg b "$BRANCH" "$DQ"' | keys | map(select(startswith($b+"."))) | sort | reverse | .[0] // empty' "$IDX")"
      { [ -n "$CAND" ] && [ "$CAND" != "null" ]; } || continue
      if [ "$BRANCH" = "580" ] && [ "$NEEDS_GSP" = "true" ]; then
        if [ -z "$GSP_FW" ] || [ "$GSP_FW" = "null" ]; then
          log "GPU $GPUID needs GSP firmware but none is bundled for it - skipping 580"; continue
        fi
        GHAVE="$(jq -r --arg d "$CAND" --arg f "$GSP_FW" '.gsp_firmware[$d].chips // [] | index($f) // empty' "$IDX" 2>/dev/null)"
        [ -n "$GHAVE" ] || { log "GPU $GPUID needs GSP firmware ($GSP_FW) but $CAND's index has none - skipping 580"; continue; }
      fi
      DRV="$CAND"; break
    done
    # Known GPU, but none of its branches exist for this platform+kernel - e.g.
    # a Kepler card on a kver4 platform, where the GPU needs 470 and only 550 is
    # built. 550 would install cleanly and drive nothing.
    if [ -z "$DRV" ] && [ "$GKNOWN" = "true" ] && [ -n "$GBRANCHES" ]; then
      log "GPU $GPUID needs one of [$GBRANCHES] but $PLATFORM/$KVER only has [$AVAIL] - nothing here will drive this GPU, skipping"
      return 1
    fi
    # No GPU detected, or its PCI id is newer than the catalog: fall back to the
    # per-kernel default (kver5 -> 580, kver4 -> 550), intersected with AVAIL.
    if [ -z "$DRV" ]; then
      KMAJ="${KVER%%.*}"
      KDEF="$(jq -r --arg k "$KMAJ" '.default_branch_by_kernel[$k] // .default_branch // empty' "$SUP" 2>/dev/null)"
      if [ -n "$KDEF" ] && [ "$KDEF" != "null" ] && has_branch "$KDEF"; then
        DRV="$(jq -r --arg p "$PLATFORM" --arg k "$KVER" --arg b "$KDEF" "$DQ"' | keys | map(select(startswith($b+"."))) | sort | reverse | .[0] // empty' "$IDX")"
        log "GPU unknown/undetected - falling back to the kernel ${KMAJ}.x default branch $KDEF"
      fi
    fi
  fi
  [ -z "$DRV" ] && DRV="$(jq -r --arg p "$PLATFORM" --arg k "$KVER" "$DQ"' | keys | sort | reverse | .[0]' "$IDX")"
  { [ -z "$DRV" ] || [ "$DRV" = "null" ]; } && { log "no driver resolved, skipping"; return 1; }
  log "resolved driver $DRV"
  WANT_FF="${nvidia_ffmpeg:-false}"
  # Container Manager (Docker) runtime integration - platform/kernel-independent,
  # one shared layer for all drivers/platforms (see nvidia-index.json.container_runtime).
  WANT_CR="${nvidia_container_runtime:-false}"
  CRF="$(jq -r '.container_runtime.file // empty' "$IDX")"
  CRSHA="$(jq -r '.container_runtime.sha256 // empty' "$IDX")"

  BASE="$(jq -r '.release_base' "$IDX")"
  KOF="$(jq   -r --arg p "$PLATFORM" --arg k "$KVER" --arg d "$DRV" "$DQ"'[$d].ko.file' "$IDX")"
  USF="$(jq   -r --arg p "$PLATFORM" --arg k "$KVER" --arg d "$DRV" "$DQ"'[$d].userspace.file' "$IDX")"
  FFF="$(jq   -r --arg p "$PLATFORM" --arg k "$KVER" --arg d "$DRV" "$DQ"'[$d].ffmpeg.file // empty' "$IDX")"
  KOSHA="$(jq -r --arg p "$PLATFORM" --arg k "$KVER" --arg d "$DRV" "$DQ"'[$d].ko.sha256' "$IDX")"
  USSHA="$(jq -r --arg p "$PLATFORM" --arg k "$KVER" --arg d "$DRV" "$DQ"'[$d].userspace.sha256' "$IDX")"
  FFFSHA="$(jq -r --arg p "$PLATFORM" --arg k "$KVER" --arg d "$DRV" "$DQ"'[$d].ffmpeg.sha256 // empty' "$IDX")"

  # GSP firmware (Turing/Ampere-GA10x only for now; see comment above). GSP_FW
  # may already be set from the loop above; re-derive it here too so the
  # `nvidia_driver` override path (which skips that loop) still gets it.
  [ -n "${GSP_FW:-}" ] || GSP_FW="$(jq -r --arg g "$GPUID" '.gpus[$g].gsp_fw // empty' "$SUP" 2>/dev/null)"
  GFF=""; GFSHA=""
  if [ -n "$GSP_FW" ] && [ "$GSP_FW" != "null" ]; then
    GHAVE="$(jq -r --arg d "$DRV" --arg f "$GSP_FW" '.gsp_firmware[$d].chips // [] | index($f) // empty' "$IDX" 2>/dev/null)"
    if [ -n "$GHAVE" ]; then
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
  if [ "$WANT_CR" = "true" ] && [ -n "$CRF" ]; then
    fetch "$BASE/$CRF" "$CACHE/$CRF" "$CRSHA" || log "container runtime layer download failed (optional)"
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
    KOF="$(jq -r --arg p "$PLATFORM" --arg k "$KVER" --arg d "$DRV" "$DQ"'[$d].ko.file' "$IDX")"
    USF="$(jq -r --arg p "$PLATFORM" --arg k "$KVER" --arg d "$DRV" "$DQ"'[$d].userspace.file' "$IDX")"
    FFF="$(jq -r --arg p "$PLATFORM" --arg k "$KVER" --arg d "$DRV" "$DQ"'[$d].ffmpeg.file // empty' "$IDX")"
    GFF=""
    if [ -n "${GSP_FW:-}" ] && [ "$GSP_FW" != "null" ]; then
      GHAVE="$(jq -r --arg d "$DRV" --arg f "$GSP_FW" '.gsp_firmware[$d].chips // [] | index($f) // empty' "$IDX" 2>/dev/null)"
      [ -n "$GHAVE" ] && GFF="$(jq -r --arg d "$DRV" '.gsp_firmware[$d].file' "$IDX")"
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
  # The kernel version goes in too: a DSM upgrade (7.1 -> 7.2) keeps the
  # platform name but moves 4.4.180 -> 4.4.302, invalidating these modules.
  echo "$PLATFORM $KVER" > "$KMODDIR/.nvidia-platform"
  # GPU architecture marker for the boot hook's Jellyfin auto-configuration.
  # nvidia-gpu-support.json only exists here in the patches/late phase (it ships
  # inside the addon, not into /tmpRoot), so the arch has to be handed forward
  # as a file the hook can read at boot. Used to pick NVDEC decode codecs.
  jq -r --arg g "$GPUID" '.gpus[$g].arch // "unknown"' "$SUP" 2>/dev/null > "$KMODDIR/.nvidia-gpuarch" || echo unknown > "$KMODDIR/.nvidia-gpuarch"

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

  # --- optional Container Manager (Docker) runtime integration ---
  # Platform/kernel-independent (one shared layer), so this can run every boot
  # this addon is active, not just on first install - do_inject re-extracts
  # unconditionally, which is fine (idempotent: same bytes each time).
  CRDIR="$TR/usr/local/nvidia-runtime"
  if [ "$WANT_CR" = "true" ] && [ -s "$CACHE/$CRF" ]; then
    rm -rf "$CRDIR"; mkdir -p "$CRDIR"
    tar -xzf "$CACHE/$CRF" -C "$CRDIR"
    chmod +x "$CRDIR"/bin/* "$CRDIR"/tools/* 2>/dev/null

    # DSM ships no ldconfig/ld.so.cache; nvidia-container-cli needs one to
    # locate the driver's libs. Build it against the /tmpRoot paths the
    # container runtime will actually see once booted.
    "$CRDIR/tools/ldconfig" -C "$CRDIR/ld.so.cache" \
      "$TR/usr/lib" "$TR/usr/local/nvidia/lib" "$CRDIR/lib" 2>/dev/null

    # nvidia-ctk's own OCI hooks hardcode --ldconfig-path=/sbin/ldconfig and
    # do not honor config.toml's ldconfig= for that default; DSM has neither
    # /sbin nor /usr/sbin/ldconfig, so fill it with the bundled static binary.
    if [ ! -e "$TR/usr/sbin/ldconfig" ]; then
      mkdir -p "$TR/usr/sbin"
      cp "$CRDIR/tools/ldconfig" "$TR/usr/sbin/ldconfig"
      chmod +x "$TR/usr/sbin/ldconfig"
    fi

    mkdir -p "$TR/etc/nvidia-container-runtime"
    cat > "$TR/etc/nvidia-container-runtime/config.toml" <<TOML
[nvidia-container-cli]
root = "/"
path = "/usr/local/nvidia-runtime/bin/nvidia-container-cli"
ldcache = "/usr/local/nvidia-runtime/ld.so.cache"
ldconfig = "@/usr/sbin/ldconfig"
environment = ["LD_LIBRARY_PATH=/usr/local/nvidia-runtime/lib"]

[nvidia-container-runtime]
runtimes = ["/var/packages/ContainerManager/target/usr/bin/runc"]

[nvidia-container-runtime-hook]
path = "/usr/local/nvidia-runtime/bin/nvidia-container-runtime-hook"

[nvidia-ctk]
path = "/usr/local/nvidia-runtime/bin/nvidia-ctk"
TOML
    log "container runtime staged -> /usr/local/nvidia-runtime, config.toml written"

    # register the 'nvidia' runtime in Container Manager's daemon.json now, if
    # the package happens to already be present in this /tmpRoot image - merge,
    # never overwrite (DSM already has bip/data-root/etc in there). The boot
    # hook below re-asserts this on every subsequent boot regardless, since
    # rc.d runs before ContainerManager's own auto-start (confirmed on real
    # hardware - kernel module load logged ~8s ahead of the package's synopkg
    # start sequence).
    DJ="$TR/var/packages/ContainerManager/etc/dockerd.json"
    if [ -f "$DJ" ]; then
      NEWDJ="$(jq '.runtimes.nvidia = {"path": "/usr/local/nvidia-runtime/bin/nvidia-container-runtime", "runtimeArgs": []}' "$DJ" 2>/dev/null)"
      [ -n "$NEWDJ" ] && echo -E "$NEWDJ" > "$DJ" && log "daemon.json: 'nvidia' runtime registered"
    fi
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
  CURK="$(uname -r | sed 's/[^0-9.].*$//')"
  STORED="$(cat /usr/lib/modules/.nvidia-platform 2>/dev/null)"
  STOREDP="${STORED%% *}"
  # markers written by older installs hold the platform only (no space)
  STOREDK=""; case "$STORED" in *" "*) STOREDK="${STORED##* }" ;; esac
  if [ -n "$STOREDP" ] && [ "$STOREDP" != "$CURP" ]; then
    rclog "SKIPPED: installed .ko are for platform '$STOREDP' but running on '$CURP' - re-select the driver for this platform"
    exit 0
  fi
  # Kernel guard: a DSM upgrade can move the same platform to a new kernel
  # (4.4.180 -> 4.4.302). insmod rejects the vermagic anyway; catching it here
  # puts the reason in the log instead of a bare failure.
  if [ -n "$STOREDK" ] && [ "$STOREDK" != "$CURK" ]; then
    rclog "SKIPPED: installed .ko are for kernel '$STOREDK' but running '$CURK' (DSM upgraded?) - re-run the addon"
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
  # Container Manager runtime integration (if do_inject set it up): re-assert
  # the 'nvidia' entry in dockerd.json on every boot, in case a DSM update or
  # config restore reverted it. rc.d runs before ContainerManager's own
  # auto-start (confirmed on real hardware, ~8s ahead), so this is already in
  # place by the time dockerd reads it - idempotent, no-op if already correct.
  CRDIR=/usr/local/nvidia-runtime
  DJ=/var/packages/ContainerManager/etc/dockerd.json
  if [ -x "$CRDIR/bin/nvidia-container-runtime" ] && [ -f "$DJ" ] && command -v jq >/dev/null 2>&1; then
    CUR="$(jq -r '.runtimes.nvidia.path // empty' "$DJ" 2>/dev/null)"
    if [ "$CUR" != "$CRDIR/bin/nvidia-container-runtime" ]; then
      NEWDJ="$(jq --arg p "$CRDIR/bin/nvidia-container-runtime" '.runtimes.nvidia = {"path": $p, "runtimeArgs": []}' "$DJ" 2>/dev/null)"
      if [ -n "$NEWDJ" ]; then
        echo -E "$NEWDJ" > "$DJ"
        rclog "container runtime: re-registered 'nvidia' in dockerd.json (was missing/stale)"
      fi
    fi
  elif [ -f "$DJ" ] && command -v jq >/dev/null 2>&1; then
    # The layer is optional (nvidia_container_runtime flag) and can be turned
    # back off from the menu, but dockerd.json is not ours and is never rebuilt
    # - so switching the flag off used to leave a registration pointing at a
    # binary that no longer exists. Docker still advertises the runtime, and
    # anything started with --runtime=nvidia then dies at exec time with
    #   fork/exec /usr/local/nvidia-runtime/bin/nvidia-container-runtime:
    #   no such file or directory
    # which gives no hint that an addon left it behind. Found exactly that
    # state on real hardware.
    #
    # Only ever removes an entry pointing at OUR path: a user who wired up
    # their own nvidia runtime somewhere else keeps it.
    CUR="$(jq -r '.runtimes.nvidia.path // empty' "$DJ" 2>/dev/null)"
    if [ "$CUR" = "$CRDIR/bin/nvidia-container-runtime" ]; then
      NEWDJ="$(jq 'del(.runtimes.nvidia)' "$DJ" 2>/dev/null)"
      if [ -n "$NEWDJ" ]; then
        echo -E "$NEWDJ" > "$DJ"
        rclog "container runtime: removed stale 'nvidia' entry from dockerd.json (layer not installed)"
      fi
    fi
  fi
  # Jellyfin package ffmpeg path: SynoCommunity's jellyfin hardcodes
  #   --ffmpeg /var/packages/ffmpeg7/target/bin/ffmpeg
  # as a *launch argument* in its service-setup. That argument outranks
  # encoding.xml and greys out the Dashboard field, so the user cannot point
  # Jellyfin at our NVENC build from the UI - and ffmpeg7's own binary has no
  # NVENC encoders, leaving transcoding on CPU.
  #
  # Re-assert it on every boot rather than only at install time: a Jellyfin
  # package update or reinstall restores the original service-setup, silently
  # reverting the path. rc.d runs before synopkgd auto-starts jellyfin
  # (measured on real hardware: modules loaded 19:09:00, jellyfin started
  # 19:09:08 - about 8s of headroom), so the patch is already in place by the
  # time jellyfin reads the file. A single sed is fast enough for that window.
  #
  # Gated on our ffmpeg actually existing: the ffmpeg layer is optional
  # (nvidia_ffmpeg flag), and pointing jellyfin at a missing binary would be
  # worse than leaving ffmpeg7 in place. Idempotent - only rewrites when the
  # file still names ffmpeg7.
  JF_SS=/var/packages/jellyfin/scripts/service-setup
  NVFF=/usr/local/nvidia/bin/ffmpeg
  if [ -x "$NVFF" ] && [ -f "$JF_SS" ] && grep -q -- '--ffmpeg /var/packages/ffmpeg7/target/bin/ffmpeg' "$JF_SS"; then
    cp -n "$JF_SS" "$JF_SS.pre-nvidia.bak" 2>/dev/null
    if sed -i "s#--ffmpeg /var/packages/ffmpeg7/target/bin/ffmpeg#--ffmpeg $NVFF#" "$JF_SS" 2>/dev/null; then
      # sed -i (and cp above) replace the file with a NEW inode built under
      # the current umask, which does NOT preserve the original 755 - caught
      # on real hardware where it landed as root:root 700. DSM runs this
      # script as the package's own service account (sc-jellyfin here, from
      # conf/privilege's run-as:"package"), so a non-executable/unreadable
      # file makes jellyfin exit within ~20s ("begin to stop due to abnormal
      # status") before it ever logs anything - looks like a crash, is really
      # a permissions regression. Force both files back to what every other
      # script in this directory already is.
      chown root:root "$JF_SS" "$JF_SS.pre-nvidia.bak" 2>/dev/null
      chmod 755 "$JF_SS" "$JF_SS.pre-nvidia.bak" 2>/dev/null
      rclog "jellyfin: ffmpeg path repointed to $NVFF (was ffmpeg7, no NVENC)"
    fi
  fi
  # Jellyfin hardware transcoding auto-configuration. Jellyfin ships with
  # hardware acceleration off and expects the user to pick NVENC by hand in
  # Dashboard -> Playback and then tick the right decode codecs - which they
  # cannot know without reading NVIDIA's per-architecture capability tables.
  # Plex just detects and enables; do the same, but GPU-model-aware (Plex is
  # not): the encoders are probed against the real card, so a Pascal box never
  # gets AV1 encoding switched on and a Kepler box never gets HEVC.
  #
  # This runs at most once. The stamp lives in jellyfin's own config directory,
  # not ours - /usr/local/nvidia is rebuilt from scratch by the addon on every
  # boot, so a stamp there would never survive; this one also disappears with
  # the package, which is the right lifetime. Once stamped, everything the user
  # subsequently changes in the UI is left alone forever.
  #
  # No stamp is written when encoding.xml does not exist yet: a freshly
  # installed jellyfin has no config until its setup wizard has been completed,
  # so this quietly retries on the next boot rather than giving up. Same for a
  # jellyfin that is somehow already running - it holds this config in memory
  # and rewrites the file on change, so editing underneath it would be undone.
  JF_CFG=/var/packages/jellyfin/var/config/encoding.xml
  JF_STAMP=/var/packages/jellyfin/var/config/.nvidia-autoconf
  JF_TTPDIR=/dev/shm/jellyfin-transcodes
  JF_PID="$(cat /var/packages/jellyfin/var/jellyfin.pid 2>/dev/null)"
  if [ -x "$NVFF" ] && [ -f "$JF_CFG" ] && [ ! -f "$JF_STAMP" ] \
     && ! { [ -n "$JF_PID" ] && [ -d "/proc/$JF_PID" ]; }; then
    JF_HW="$(sed -n 's#.*<HardwareAccelerationType>\([^<]*\)</HardwareAccelerationType>.*#\1#p' "$JF_CFG" 2>/dev/null)"
    if [ -n "$JF_HW" ] && [ "$JF_HW" != "none" ]; then
      # Already configured by hand - record that and never look again.
      : > "$JF_STAMP" 2>/dev/null
      rclog "jellyfin: hardware acceleration already set to '$JF_HW' - left as is"
    else
      # Ask the card itself what it can encode. Each probe is a 1-frame encode
      # to /dev/null and takes ~0.5s on real hardware; the boot hook has ~8s of
      # headroom before synopkgd starts jellyfin. timeout is belt-and-braces so
      # a wedged probe can never hold up the package start.
      nvprobe(){ timeout 15 "$NVFF" -hide_banner -loglevel quiet \
        -f lavfi -i nullsrc=s=128x128:d=0.04 -c:v "$1" -f null - >/dev/null 2>&1; }
      JF_HEVC=false; nvprobe hevc_nvenc && JF_HEVC=true
      JF_AV1=false;  nvprobe av1_nvenc  && JF_AV1=true
      # NVDEC decode support is not probeable the same way (it would need real
      # encoded input per codec), so it comes from the architecture instead.
      # Erring generous is safe here: ffmpeg silently falls back to software
      # decode for a codec the chip cannot handle, whereas leaving a supported
      # codec off would cost performance permanently and invisibly.
      JF_ARCH="$(cat /usr/lib/modules/.nvidia-gpuarch 2>/dev/null)"
      JF_DEC="h264 vc1 mpeg2video mpeg4"
      case "$JF_ARCH" in
        Kepler)                   ;;
        Maxwell)                  JF_DEC="$JF_DEC vp8 hevc" ;;
        Ampere*|Ada|Blackwell)    JF_DEC="$JF_DEC vp8 hevc vp9 av1" ;;
        *)                        JF_DEC="$JF_DEC vp8 hevc vp9" ;;
      esac
      # Preserve ownership across the edits below: this file belongs to the
      # package's service account (sc-jellyfin), and both sed -i and the awk
      # rewrite replace it with a new inode owned by root - the same class of
      # regression that made jellyfin fail to start when service-setup lost its
      # mode bits. A root-owned encoding.xml would stop jellyfin from ever
      # saving playback settings from the UI again.
      JF_OWN="$(stat -c '%U:%G' "$JF_CFG" 2>/dev/null)"
      # Three forms have to be covered, all of which a real jellyfin config
      # actually contains: a bare self-closing element (<QsvDevice />), one
      # .NET serialised as nil and so self-closing *with an attribute*
      # (<EncoderPreset xsi:nil="true" />), and an ordinary element carrying a
      # value. Requiring a space or '/' straight after the tag name keeps a
      # name from matching a longer one that starts with it. Delimiter is #
      # because one of the values is a path.
      jfset(){ sed -i \
        -e "s#<$1 */>#<$1>$2</$1>#" \
        -e "s#<$1 [^>]*/>#<$1>$2</$1>#" \
        -e "s#<$1>[^<]*</$1>#<$1>$2</$1>#" "$JF_CFG" 2>/dev/null; }
      jfset HardwareAccelerationType   nvenc
      jfset EnableHardwareEncoding     true
      jfset EnableEnhancedNvdecDecoder true
      jfset AllowHevcEncoding          "$JF_HEVC"
      jfset AllowAv1Encoding           "$JF_AV1"
      jfset EnableTonemapping          true
      jfset EncoderAppPathDisplay      "$NVFF"
      # Encoder preset. Measured on real hardware (P620, entry-level Pascal,
      # 1080p30 hevc_nvenc): p1 10.6x, p4 9.86x, p5 9.35x, p6 9.27x, p7 8.83x -
      # only 17% between fastest and slowest. NVENC quality presets are nearly
      # free because the work happens in fixed-function silicon, so the usual
      # x264 instinct of trading quality for throughput does not apply. slow
      # (p5) still sustains ~9 simultaneous 1080p streams on the weakest card
      # this addon supports, and Jellyfin maps its preset names straight onto
      # p1-p7 (fast=p3, medium=p4, slow=p5, slower=p6, veryslow=p7).
      jfset EncoderPreset              slow
      # Transcoding scratch space in RAM. This is a real win - HLS segments are
      # written and deleted constantly, and keeping that off the array avoids
      # waking disks and burning SSD writes - but it is only safe when the
      # transcode cannot outrun the player. At the speeds measured above ffmpeg
      # renders a 2-hour movie into /dev/shm in about 13 minutes, which would
      # fill a 3.8G tmpfs several times over, so throttling (pause once far
      # enough ahead of the playhead) and segment deletion (drop what has been
      # played) go on with it. Skipped entirely on a small /dev/shm: below a
      # couple of GB even a throttled 4K stream has no comfortable headroom,
      # and the default on-disk path is the safer answer there.
      JF_SHM="$(df -m /dev/shm 2>/dev/null | awk 'NR==2{print $2}')"
      if [ -d /dev/shm ] && [ -n "$JF_SHM" ] && [ "$JF_SHM" -ge 2048 ] 2>/dev/null; then
        # Unlike every other key here, TranscodingTempPath is simply absent
        # from a config jellyfin has just created - there is nothing to
        # substitute, so it has to be inserted. Position matters: .NET's
        # XmlSerializer expects elements in schema order and quietly ignores
        # ones that arrive out of sequence, so it goes immediately after
        # EncodingThreadCount, where jellyfin itself writes it.
        # A dedicated subdirectory, never /dev/shm itself. Jellyfin treats the
        # transcode path as exclusively its own and its cleanup task empties
        # it wholesale - pointed at /dev/shm that means trying to delete
        # everything else living in the same tmpfs. On real hardware that is
        # Plex's /dev/shm/Transcode, DSM's PostgreSQL shared memory segment and
        # nginx's scratch file; the attempts only fail because jellyfin runs
        # unprivileged, which is luck rather than design.
        if grep -q "<TranscodingTempPath[ >/]" "$JF_CFG" 2>/dev/null; then
          jfset TranscodingTempPath  "$JF_TTPDIR"
        else
          sed -i "s#</EncodingThreadCount>#</EncodingThreadCount>\n  <TranscodingTempPath>$JF_TTPDIR</TranscodingTempPath>#" "$JF_CFG" 2>/dev/null
        fi
        jfset EnableThrottling       true
        jfset EnableSegmentDeletion  true
        JF_TMP="$JF_TTPDIR (${JF_SHM}MB tmpfs, throttling+segment deletion on)"
      else
        JF_TMP="default on-disk (/dev/shm ${JF_SHM:-absent}MB, too small)"
      fi
      # HardwareDecodingCodecs is a list, so it needs the whole element
      # replaced rather than a value substitution - and it may be empty and
      # self-closing on a config jellyfin has never had acceleration set on.
      awk -v list="$JF_DEC" '
        function emit(  n,a,i) {
          print "  <HardwareDecodingCodecs>"
          n = split(list, a, " ")
          for (i = 1; i <= n; i++) print "    <string>" a[i] "</string>"
          print "  </HardwareDecodingCodecs>"
        }
        /<HardwareDecodingCodecs *\/>/            { emit(); next }
        /<HardwareDecodingCodecs>/                { emit(); skip = 1; next }
        skip && /<\/HardwareDecodingCodecs>/      { skip = 0; next }
        skip                                      { next }
                                                  { print }
      ' "$JF_CFG" > "$JF_CFG.nvtmp" 2>/dev/null \
        && [ -s "$JF_CFG.nvtmp" ] && mv -f "$JF_CFG.nvtmp" "$JF_CFG"
      rm -f "$JF_CFG.nvtmp" 2>/dev/null
      [ -n "$JF_OWN" ] && chown "$JF_OWN" "$JF_CFG" 2>/dev/null
      chmod 644 "$JF_CFG" 2>/dev/null
      : > "$JF_STAMP" 2>/dev/null
      [ -n "$JF_OWN" ] && chown "$JF_OWN" "$JF_STAMP" 2>/dev/null
      rclog "jellyfin: NVENC auto-configured (arch=${JF_ARCH:-unknown} hevc=$JF_HEVC av1=$JF_AV1 preset=slow tmp=$JF_TMP decode='$JF_DEC')"
    fi
  fi
  # Transcode scratch directory, every boot - deliberately outside the one-shot
  # block above. /dev/shm is a tmpfs and comes up empty, so a path that lives
  # there has to be recreated before jellyfin starts, on every boot, for as
  # long as the config points at it. Reads the path back out of the config
  # rather than assuming ours, so a hand-picked tmpfs path is handled too.
  if [ -f "$JF_CFG" ]; then
    JF_TTP="$(sed -n 's#.*<TranscodingTempPath>\([^<]*\)</TranscodingTempPath>.*#\1#p' "$JF_CFG" 2>/dev/null)"
    case "$JF_TTP" in
      /dev/shm/?*)
        if [ ! -d "$JF_TTP" ]; then
          mkdir -p "$JF_TTP" 2>/dev/null
          JF_DOWN="$(stat -c '%U:%G' /var/packages/jellyfin/var/config 2>/dev/null)"
          [ -n "$JF_DOWN" ] && chown "$JF_DOWN" "$JF_TTP" 2>/dev/null
          chmod 755 "$JF_TTP" 2>/dev/null
          rclog "jellyfin: created transcode scratch $JF_TTP (tmpfs starts empty)"
        fi
        ;;
    esac
  fi
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
