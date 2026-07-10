#!/usr/bin/env bash
#
# Copyright (C) 2022 Ing <https://github.com/wjz304>
# MSHELL adaptation: replaces wjz304's synoscgiproxy with mshellscgiproxy,
# an intercepting proxy that augments DSM API responses with the loader
# version read from /usr/mshell/VERSION.
#
# This is free software, licensed under the MIT License.
# See /LICENSE for more information.
#

FILE_JS="/usr/syno/synoman/webman/modules/AdminCenter/admin_center.js"
FILE_GZ="${FILE_JS}.gz"

PROXY_BIN="/usr/sbin/mshellscgiproxy"
PROXY_SOCK_NAME="synoscgi_ms"

# GPU info handed to mshellscgiproxy for DSM 7.4. 7.4 rewrote the Info Center
# GPU section to render from the SYNO.Core.System response fields
# support_gpu + gpu_info[] instead of the 7.3 client-side t.gpu object. We
# resolve the GPU here (lspci name + sysfs clock/memory) and drop a gpu_info
# array into this file; the proxy injects it (plus support_gpu) into the live
# response. The legacy admin_center.js patch below still covers DSM <= 7.3,
# which ignores the unknown response fields.
GPU_INFO_FILE="/run/mshell_gpu_info.json"

# PCI_SLOT_FILE holds the SYNO.Core.System "external_pci_slot_info" array
# (PCIe slot occupancy) precomputed here: each add-in PCIe device (an endpoint
# behind a root-port bridge, i.e. not on bus 00) is resolved to a device name
# and presented as an occupied slot. mshellscgiproxy replaces the genuine
# (all-"no") external_pci_slot_info in the SYNO.Core.System.info response with
# this array so the Info Center's "PCIe 슬롯 N" rows show the device name.
PCI_SLOT_FILE="/run/mshell_pci_slot_info.json"

# repoint_nginx redirects nginx's primary synoscgi SCGI upstream to the
# intercepting proxy socket. It is idempotent and migration-safe: any prior
# proxy socket name — RR's legacy synoscgi_rr.sock or our own synoscgi_ms.sock
# — is first collapsed back to the canonical synoscgi.sock, so (a) the .bak
# snapshot always holds the pristine, proxy-free config and (b) repeated runs
# never strand nginx on a dead socket (e.g. an RR leftover) regardless of
# whether the proxy was already running.
repoint_nginx() {
  local f
  for f in /etc/nginx/nginx.conf /usr/syno/share/nginx/nginx.mustache; do
    [ -f "${f}" ] || continue
    [ ! -f "${f}.bak" ] && cp -pf "${f}" "${f}.bak"
    # Keep the backup pristine (collapse any proxy socket to canonical).
    sed -i 's|/run/synoscgi_rr\.sock;|/run/synoscgi.sock;|g; s|/run/synoscgi_ms\.sock;|/run/synoscgi.sock;|g' "${f}.bak"
    # Normalize the live file, then repoint to our proxy socket.
    sed -i 's|/run/synoscgi_rr\.sock;|/run/synoscgi.sock;|g; s|/run/synoscgi_ms\.sock;|/run/synoscgi.sock;|g' "${f}"
    sed -i "s|/run/synoscgi.sock;|/run/${PROXY_SOCK_NAME}.sock;|g" "${f}"
  done
}

# restore_nginx reverts to the pristine upstream and removes the backup. It
# also collapses any stray proxy socket name in case the backup predates the
# migration-safe logic above.
restore_nginx() {
  local f
  for f in /etc/nginx/nginx.conf /usr/syno/share/nginx/nginx.mustache; do
    [ -f "${f}.bak" ] && mv -f "${f}.bak" "${f}"
    [ -f "${f}" ] || continue
    sed -i 's|/run/synoscgi_rr\.sock;|/run/synoscgi.sock;|g; s|/run/synoscgi_ms\.sock;|/run/synoscgi.sock;|g' "${f}"
  done
}

# _gpu_name_fallback resolves a GPU display name from PCI vendor:device IDs
# when lspci's pci.ids database is missing/outdated and only prints the raw
# "Device <vid>:<did>". Newer (2021+) Intel desktop iGPUs (Alder/Raptor Lake)
# are the common victims. A curated table gives exact marketing names; anything
# else falls back to a vendor-prefixed label so the result is never wrong.
# Args: $1=vid (4 hex, no 0x), $2=did
_gpu_name_fallback() {
  local vid="$1" did="$2" dev="" vendor=""
  case "${vid}:${did}" in
    8086:5902) dev="Kaby Lake-S GT1 [HD Graphics 610]" ;;
    8086:5912) dev="Kaby Lake-S GT2 [HD Graphics 630]" ;;
    8086:3e90|8086:3e93) dev="CoffeeLake-S GT1 [UHD Graphics 610]" ;;
    8086:3e91|8086:3e92|8086:3e98) dev="CoffeeLake-S GT2 [UHD Graphics 630]" ;;
    8086:9ba8) dev="CometLake-S GT1 [UHD Graphics 610]" ;;
    8086:9bc5|8086:9bc8) dev="CometLake-S GT2 [UHD Graphics 630]" ;;
    8086:4c8a) dev="RocketLake-S GT1 [UHD Graphics 750]" ;;
    8086:4c8b) dev="RocketLake-S GT1 [UHD Graphics 730]" ;;
    8086:4680|8086:4690) dev="Alder Lake-S GT1 [UHD Graphics 770]" ;;
    8086:4682|8086:4692) dev="Alder Lake-S GT1 [UHD Graphics 730]" ;;
    8086:4693) dev="Alder Lake-S GT1 [UHD Graphics 710]" ;;
    8086:46d0|8086:46d1|8086:46d2) dev="Alder Lake-N [UHD Graphics]" ;;
    8086:a780) dev="Raptor Lake-S GT1 [UHD Graphics 770]" ;;
    8086:a781|8086:a782|8086:a783|8086:a788|8086:a789|8086:a78a|8086:a78b) dev="Raptor Lake-S [UHD Graphics]" ;;
    1002:6985) dev="Lexa XT [Radeon PRO WX 3100]" ;;
  esac
  case "${vid}" in
    8086) vendor="Intel Corporation" ;;
    10de) vendor="NVIDIA Corporation" ;;
    1002) vendor="Advanced Micro Devices, Inc. [AMD/ATI]" ;;
  esac
  if [ -n "${dev}" ]; then
    printf '%s %s' "${vendor:-Vendor ${vid}}" "${dev}"
  elif [ -n "${vendor}" ]; then
    printf '%s Graphics [%s:%s]' "${vendor}" "${vid}" "${did}"
  else
    printf 'Device [%s:%s]' "${vid}" "${did}"
  fi
}

# _pci_name resolves a PCI device display name from vendor:device IDs, mirroring
# _gpu_name_fallback. lspci is tried first; when pci.ids is missing/outdated it
# only yields "Device <ids>" (or nothing), so a curated table + vendor label is
# used, always suffixed with "[vid:did]". Args: $1=vid $2=did (4 hex, no 0x)
_pci_name() {
  local vid="$1" did="$2" dev="" vendor="" name=""
  # Try lspci first (present + pci.ids populated → real marketing name).
  name="$(lspci -d "${vid}:${did}" 2>/dev/null | head -1 | sed 's/^[0-9a-f:.]* [^:]*: //; s/ *(rev [0-9a-fA-F]*)//')"
  if [ -n "${name}" ] && ! printf '%s' "${name}" | grep -qiE '^Device '; then
    printf '%s [%s:%s]' "${name}" "${vid}" "${did}"; return
  fi
  case "${vid}:${did}" in
    10ec:8168|10ec:8161|10ec:8169) dev="RTL8111/8168/8411 Gigabit Ethernet" ;;
    10ec:8125) dev="RTL8125 2.5GbE" ;;
    10ec:8126) dev="RTL8126 5GbE" ;;
    8086:1533) dev="I210 Gigabit Network" ;;
    8086:1539) dev="I211 Gigabit Network" ;;
    8086:1521) dev="I350 Gigabit Network" ;;
    8086:10d3) dev="82574L Gigabit Network" ;;
    8086:1572|8086:1583|8086:1584|8086:1585) dev="X710/XL710 10/40GbE" ;;
    8086:1563|8086:15d1) dev="X550 10GbE" ;;
    15b3:1015|15b3:1017) dev="ConnectX-4/5 25/100GbE" ;;
  esac
  case "${vid}" in
    8086) vendor="Intel" ;;
    10ec) vendor="Realtek" ;;
    10de) vendor="NVIDIA" ;;
    1002) vendor="AMD/ATI" ;;
    1b21|1b4b) vendor="ASMedia/Marvell" ;;
    1000) vendor="Broadcom/LSI" ;;
    9005) vendor="Adaptec" ;;
    15b3) vendor="Mellanox" ;;
    1c5c|144d|1cc1|1e0f|c0a9) vendor="NVMe SSD" ;;
  esac
  if [ -n "${dev}" ]; then
    printf '%s %s [%s:%s]' "${vendor:-Vendor ${vid}}" "${dev}" "${vid}" "${did}"
  elif [ -n "${vendor}" ]; then
    printf '%s Device [%s:%s]' "${vendor}" "${vid}" "${did}"
  else
    printf 'Device [%s:%s]' "${vid}" "${did}"
  fi
}

# _pci_slot_info prints the external_pci_slot_info JSON array. An "add-in PCIe
# card" is any endpoint function 0 that sits behind a root-port bridge (bus !=
# 00) and is not itself a bridge. Slots are numbered 1..N in PCI address order.
# Prints "[]" when none are found.
_pci_slot_info() {
  local D bdf bus cls vid did nm elems="" slot=0 e
  for D in $(ls -d /sys/bus/pci/devices/0000:* 2>/dev/null | sort); do
    bdf="$(basename "${D}")"
    bus="$(echo "${bdf}" | cut -d: -f2)"
    [ "${bus}" = "00" ] && continue                 # onboard/root complex → skip
    cls="$(cat "${D}/class" 2>/dev/null)"
    case "${cls}" in 0x0604*|0x0600*|0x0601*) continue ;; esac  # bridges → skip
    [ "${bdf##*.}" = "0" ] || continue              # multifunction: function 0 only
    vid="$(sed 's/^0x//' "${D}/vendor" 2>/dev/null)"
    did="$(sed 's/^0x//' "${D}/device" 2>/dev/null)"
    [ -n "${vid}" ] && [ -n "${did}" ] || continue
    nm="$(_pci_name "${vid}" "${did}")"
    slot=$((slot + 1))
    e="$(printf '{"slot":"%s","Occupied":"yes","Recognized":"yes","cardName":"%s"}' \
      "${slot}" "$(_json_escape "${nm}")")"
    [ -z "${elems}" ] && elems="${e}" || elems="${elems},${e}"
  done
  printf '[%s]' "${elems}"
}

if [ ! -f "${FILE_JS}" ] && [ ! -f "${FILE_GZ}" ]; then
  echo "File ${FILE_JS} does not exist"
  exit 0
fi

if [ "${1}" = "-r" ]; then
  rm -f "${GPU_INFO_FILE}" "${PCI_SLOT_FILE}"
  if [ -f "${FILE_GZ}.bak" ]; then
    rm -f "${FILE_JS}" "${FILE_GZ}"
    mv -f "${FILE_GZ}.bak" "${FILE_GZ}"
    gzip -dc "${FILE_GZ}" >"${FILE_JS}"
  elif [ -f "${FILE_JS}.bak" ]; then
    mv -f "${FILE_JS}.bak" "${FILE_JS}"
  fi
  if ps -aux | grep -v grep | grep -q "${PROXY_BIN}" >/dev/null; then
    /usr/bin/pkill -f "${PROXY_BIN}"
  fi
  restore_nginx
  systemctl reload nginx
else
  if [ -f "${FILE_GZ}" ]; then
    [ ! -f "${FILE_GZ}.bak" ] && cp -pf "${FILE_GZ}" "${FILE_GZ}.bak"
  else
    [ ! -f "${FILE_JS}.bak" ] && cp -pf "${FILE_JS}" "${FILE_JS}.bak"
  fi

  rm -f "${FILE_JS}"
  if [ -f "${FILE_GZ}.bak" ]; then
    gzip -dc "${FILE_GZ}.bak" >"${FILE_JS}"
  else
    cp -pf "${FILE_JS}.bak" "${FILE_JS}"
  fi

  # CPU/GPU info is always patched statically. mshellscgiproxy only injects
  # firmware_ver / sys_temp / fan_list into the runtime API response, so the
  # vendor/family/series/cores/clock values still need to live in admin_center.js.
  VENDOR="" # str
  FAMILY="" # str
  SERIES="" # str
  CORES=""  # str
  SPEED=""  # int
  IFS=' ' read -ra models <<<"$(grep -m1 'model name' /proc/cpuinfo 2>/dev/null | cut -d: -f2 | xargs)"
  for P in "${models[@]}"; do
    PL=$(echo "${P}" | sed 's/.*/\L&/')
    if [[ "${PL:0:1}" == "@" ]] || [[ "${PL:0:1}" == "-" ]] || [[ "${PL}" == "with" ]] || [[ "${PL}" == "w/" ]]; then
      break
    fi
    if [[ "${PL}" == "cpu" ]] || [[ "${PL}" == "processor" ]] || [[ "${PL}" == gen* ]] || [[ "${PL}" == *th ]] || [[ "${PL}" == *-core* ]]; then
      continue
    fi
    if [[ -z "${VENDOR}" ]]; then
      VENDOR="${P}"
    elif [[ -z "${FAMILY}" ]]; then
      FAMILY="${P}"
    elif [[ -z "${SERIES}" ]]; then
      SERIES="${P}"
    else
      SERIES="${SERIES} ${P}"
    fi
  done

  CORES="$(grep -c 'core id' /proc/cpuinfo 2>/dev/null)C\/$(grep -c 'processor' /proc/cpuinfo 2>/dev/null)T"
  SPEED="$(grep 'MHz' /proc/cpuinfo 2>/dev/null | cut -d: -f2 | cut -d. -f1 | awk '{sum+=$1; count++} END {if(count>0) printf "%.0f", sum/count; else print "0"}')"
  SPEED="${SPEED:-0}"
  sed -i "s/\(\(,\)\|\((\)\).\.cpu_vendor/\1\"${VENDOR//\"/}\"/g" "${FILE_JS}"
  sed -i "s/\(\(,\)\|\((\)\).\.cpu_family/\1\"${FAMILY//\"/}\"/g" "${FILE_JS}"
  sed -i "s/\(\(,\)\|\((\)\).\.cpu_series/\1\"${SERIES//\"/}\"/g" "${FILE_JS}"
  sed -i "s/\(\(,\)\|\((\)\).\.cpu_cores/\1\"${CORES//\"/}\"/g" "${FILE_JS}"
  sed -i "s/\(\(,\)\|\((\)\).\.cpu_clock_speed/\1${SPEED//\"/}/g" "${FILE_JS}"
  echo "CPU Info set to: \"${VENDOR}\" \"${FAMILY}\" \"${SERIES}\" \"${CORES}\" @ ${SPEED} MHz"

  # Start from a clean slate so a GPU-less host (or a removed card) never
  # leaves stale gpu_info / pci_slot_info for the proxy to inject.
  rm -f "${GPU_INFO_FILE}" "${PCI_SLOT_FILE}"

  # Accumulate one JSON object per GPU into GPU_ELEMS (comma-joined). FIRST_*
  # captures the first GPU for the legacy DSM <= 7.3 single-object t.gpu path.
  # status="compatible" makes formatGpuDisplayName() show the bare name (any
  # other/absent status falls through to a "(unknown)" suffix). built_in_gpu_slot_num
  # / name / clock / memory map to formatGpuInfo()'s destructured fields.
  GPU_ELEMS=""
  FIRST_NAME=""; FIRST_CLOCK=""; FIRST_MEMORY=""
  _json_escape() { printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'; }
  _append_gpu() { [ -z "${GPU_ELEMS}" ] && GPU_ELEMS="$1" || GPU_ELEMS="${GPU_ELEMS},$1"; }

  # 1. DRM cards (Intel i915 / AMD amdgpu). NVIDIA is skipped here and handled
  #    via nvidia-smi below, since its proprietary driver exposes no
  #    /sys/class/drm/card* node unless nvidia-drm modeset=1.
  for CARDN in /sys/class/drm/card[0-9]*; do
    [ -d "${CARDN}" ] || continue
    case "${CARDN##*/}" in *-*) continue ;; esac          # skip connector nodes (card0-DP-1)
    DRV="$(awk -F= '/^DRIVER=/{print $2}' "${CARDN}/device/uevent" 2>/dev/null)"
    case "${DRV}" in nvidia|nvidia-drm) continue ;; esac
    PCIDN="$(awk -F= '/PCI_SLOT_NAME/ {print $2}' "${CARDN}/device/uevent" 2>/dev/null)"
    # Strip the trailing " (rev NN)" revision suffix that lspci appends.
    GNAME="$(lspci -s ${PCIDN:-"99:99.9"} 2>/dev/null | sed "s/.*: //" | sed "s/ *(rev [0-9a-fA-F]*)//")"
    # When pci.ids is missing/outdated lspci yields the raw "Device <ids>" (or
    # nothing); rebuild the name from the sysfs PCI vendor/device IDs.
    if [ -z "${GNAME}" ] || printf '%s' "${GNAME}" | grep -qiE '^Device '; then
      GVID="$(sed 's/^0x//' "${CARDN}/device/vendor" 2>/dev/null)"
      GDID="$(sed 's/^0x//' "${CARDN}/device/device" 2>/dev/null)"
      [ -n "${GVID}" ] && [ -n "${GDID}" ] && GNAME="$(_gpu_name_fallback "${GVID}" "${GDID}")"
    fi
    GCLOCK="0 MHz"
    # Intel i915: gt_max_freq_mhz already holds the max in MHz.
    [ -f "${CARDN}/gt_max_freq_mhz" ] && GCLOCK="$(cat "${CARDN}/gt_max_freq_mhz" 2>/dev/null) MHz"
    # AMD amdgpu: pp_dpm_sclk lists every DPM state; the '*' marks the CURRENT
    # (often idle) state and each value carries its own "Mhz" unit. Pick the
    # numeric MAX across all states and append the unit once.
    if [ -f "${CARDN}/device/pp_dpm_sclk" ]; then
      GMHZ="$(awk '{v=$2; gsub(/[^0-9]/,"",v); if(v+0>m)m=v+0} END{print m}' "${CARDN}/device/pp_dpm_sclk" 2>/dev/null)"
      [ -n "${GMHZ}" ] && [ "${GMHZ}" != "0" ] && GCLOCK="${GMHZ} MHz"
    fi
    # Memory: the PCI BAR aperture is only the (possibly non-ReBAR, small)
    # window, not the real VRAM size. Prefer amdgpu's reported VRAM total, then
    # the amdgpu boot log, and fall back to the BAR aperture (e.g. Intel iGPU).
    GMEM=""
    if [ -f "${CARDN}/device/mem_info_vram_total" ]; then
      GVB="$(tr -dc '0-9' < "${CARDN}/device/mem_info_vram_total" 2>/dev/null)"
      [ -n "${GVB}" ] && [ "${GVB}" != "0" ] && GMEM="$((GVB / 1048576)) MiB"
    fi
    if [ -z "${GMEM}" ] && [ -n "${PCIDN}" ]; then
      GVM="$(dmesg 2>/dev/null | grep -E "${PCIDN}.* VRAM: [0-9]+M" | head -1 | sed -E 's/.* VRAM: ([0-9]+)M.*/\1/')"
      [ -n "${GVM}" ] && GMEM="${GVM} MiB"
    fi
    [ -z "${GMEM}" ] && GMEM="$(awk '{s=(strtonum($2)-strtonum($1)+1)/1048576} (and(strtonum($3),0x200))&&(and(strtonum($3),0x2000))&&(and(strtonum($3),0x40000))&&s>0{print int(s) " MiB"; exit}' "${CARDN}/device/resource" 2>/dev/null)"
    [ -n "${GNAME}" ] && [ -n "${GCLOCK}" ] && [ -n "${GMEM}" ] || continue
    [ -z "${FIRST_NAME}" ] && { FIRST_NAME="${GNAME}"; FIRST_CLOCK="${GCLOCK}"; FIRST_MEMORY="${GMEM}"; }
    # GPU temperature via hwmon (Intel i915 / AMD amdgpu). Values are in
    # millidegrees C; divide by 1000. Walk hwmon* subdirs and pick the first
    # temp1_input that reports a sane (> 0) value.
    GTEMP=""
    for _HTMP in "${CARDN}/device/hwmon"/hwmon*/temp1_input; do
      [ -f "${_HTMP}" ] || continue
      _TV="$(cat "${_HTMP}" 2>/dev/null)"
      [ -n "${_TV}" ] && [ "${_TV}" -gt 0 ] 2>/dev/null && { GTEMP="$((_TV / 1000))"; break; }
    done
    echo "GPU Info (drm) set to: \"${GNAME}\" \"${GCLOCK}\" \"${GMEM}\"${GTEMP:+ ${GTEMP}C}${PCIDN:+ [${PCIDN}]}"
    # The slot VALUE carries the PCIe device name (GNAME) so the Info Center's
    # GPU-slot row shows a name instead of "0"/an address — consistent with the
    # PCIe 슬롯 rows. i915 (integrated) keeps built_in_gpu_slot_num so the label
    # stays "GPU 슬롯 (기본 제공)"; discrete cards use pci_slot_num ("PCIe 슬롯").
    # The proxy also keys its iGPU temperature fallback off built_in_gpu_slot_num.
    _GNAME_J="$(_json_escape "${GNAME}")"
    if [ "${DRV}" = "i915" ] || [ -z "${PCIDN}" ]; then
      _GSLOT='"built_in_gpu_slot_num":"'"${_GNAME_J}"'"'
    else
      _GSLOT='"pci_slot_num":"'"${_GNAME_J}"'"'
    fi
    if [ -n "${GTEMP}" ]; then
      _append_gpu "$(printf '{"name":"%s","status":"compatible","clock":"%s","memory":"%s",%s,"temperature_c":%s,"tempwarn":false}' \
        "$(_json_escape "${GNAME}")" "${GCLOCK}" "${GMEM}" "${_GSLOT}" "${GTEMP}")"
    else
      # No DRM hwmon temp read here. DSM 7.4's formatGpuInfo only renders the
      # thermal row when BOTH temperature_c AND tempwarn are defined, so emit
      # tempwarn:false. temperature_c is supplied by the proxy (package temp for
      # integrated GPUs / per-card hwmon for discrete); with both present the row
      # renders and shows the temperature.
      _append_gpu "$(printf '{"name":"%s","status":"compatible","clock":"%s","memory":"%s",%s,"tempwarn":false}' \
        "$(_json_escape "${GNAME}")" "${GCLOCK}" "${GMEM}" "${_GSLOT}")"
    fi
  done

  # 2. NVIDIA via nvidia-smi (proprietary driver). One row per GPU:
  #    name, max graphics clock (MHz), total memory (MiB), temperature (C), pci.bus_id.
  if command -v nvidia-smi >/dev/null 2>&1 && ls /dev/nvidia[0-9]* >/dev/null 2>&1; then
    while IFS=, read -r NVN NVC NVM NVT NVPCI; do
      NVN="$(printf '%s' "${NVN}" | sed 's/^ *//; s/ *$//')"
      NVC="$(printf '%s' "${NVC}" | tr -dc '0-9')"
      NVM="$(printf '%s' "${NVM}" | tr -dc '0-9')"
      NVT="$(printf '%s' "${NVT}" | tr -dc '0-9')"
      # nvidia-smi pci.bus_id: "00000000:01:00.0" → strip leading 4 zeros → "0000:01:00.0"
      NVPCI="$(printf '%s' "${NVPCI}" | tr -d ' ' | cut -c5-)"
      [ -n "${NVN}" ] || continue
      NVNAME="NVIDIA ${NVN}"; NVCLOCK="${NVC:-0} MHz"; NVMEM="${NVM:-0} MiB"
      [ -z "${FIRST_NAME}" ] && { FIRST_NAME="${NVNAME}"; FIRST_CLOCK="${NVCLOCK}"; FIRST_MEMORY="${NVMEM}"; }
      echo "GPU Info (nvidia) set to: \"${NVNAME}\" \"${NVCLOCK}\" \"${NVMEM}\" ${NVT:-?}C${NVPCI:+ [${NVPCI}]}"
      # temperature_c + tempwarn (both must be defined for the temp row to render).
      if [ -n "${NVT}" ]; then
        _append_gpu "$(printf '{"name":"%s","status":"compatible","clock":"%s","memory":"%s","pci_slot_num":"%s","temperature_c":%s,"tempwarn":false}' \
          "$(_json_escape "${NVNAME}")" "${NVCLOCK}" "${NVMEM}" "${NVPCI:-}" "${NVT}")"
      else
        _append_gpu "$(printf '{"name":"%s","status":"compatible","clock":"%s","memory":"%s","pci_slot_num":"%s"}' \
          "$(_json_escape "${NVNAME}")" "${NVCLOCK}" "${NVMEM}" "${NVPCI:-}")"
      fi
    done < <(nvidia-smi --query-gpu=name,clocks.max.graphics,memory.total,temperature.gpu,pci.bus_id --format=csv,noheader,nounits 2>/dev/null)
  fi

  if [ -n "${GPU_ELEMS}" ]; then
    # DSM <= 7.3 path: inject the first GPU as the t.gpu object client-side
    # (gated by the support_nvidia_gpu||true patch below).
    sed -i 's|t=this.getActiveApi(t);let|t=this.getActiveApi(t);if(!t.gpu){t.gpu={};t.gpu.clock="'"${FIRST_CLOCK}"'";t.gpu.memory="'"${FIRST_MEMORY}"'";t.gpu.name="'"${FIRST_NAME}"'";}let|g' "${FILE_JS}"
    # DSM 7.4 path: hand the gpu_info[] array to the proxy (see GPU_INFO_FILE).
    printf '[%s]\n' "${GPU_ELEMS}" >"${GPU_INFO_FILE}"
  fi

  # PCIe slot occupancy → external_pci_slot_info for the proxy. Written only
  # when at least one add-in PCIe card is present; a "[]" result leaves the file
  # absent so the proxy keeps the genuine (empty) slot info. (Defined here,
  # after _json_escape, which _pci_slot_info depends on.)
  _PCISLOTS="$(_pci_slot_info)"
  if [ -n "${_PCISLOTS}" ] && [ "${_PCISLOTS}" != "[]" ]; then
    printf '%s\n' "${_PCISLOTS}" >"${PCI_SLOT_FILE}"
    echo "PCIe slot info set to: ${_PCISLOTS}"
  fi

  # ── GPU section gate + GPU temp ─────────────────────────────────────────────
  if grep -q 'support_nvidia_gpu' "${FILE_JS}"; then
    # DSM <= 7.3: force GPU section visible; append temp to single t.gpu object.
    sed -i 's/_D("support_nvidia_gpu")},/_D("support_nvidia_gpu")||true},/g' "${FILE_JS}"
    sed -i 's/,C,D);/,C,t.gpu.temperature_c?D+" \| "+this.renderTempFromC(t.gpu.temperature_c):D);/g' "${FILE_JS}"
  else
    # DSM 7.4: patch formatGpuInfo() so each GPU row shows "보통 | 62 °C / 143 °F"
    # instead of just "보통". The ternary (u?over:normal) is wrapped and the
    # actual temp string from renderTempFromC(h) is appended conditionally.
    if grep -q 'u?_T("system","over_temperature"):_T("helpbrowser","font_normal"),"</div>","</div>"].join' "${FILE_JS}"; then
      # Append the temperature to the thermal status: "보통 | 54 °C / 129 °F".
      # For an integrated iGPU (no own sensor) temperature_c is the CPU package
      # temp injected by the proxy; discrete GPUs use their real hwmon temp.
      sed -i 's#u?_T("system","over_temperature"):_T("helpbrowser","font_normal"),"</div>","</div>"].join#(u?_T("system","over_temperature"):_T("helpbrowser","font_normal"))+(h?" | "+this.renderTempFromC(h):""),"</div>","</div>"].join#g' "${FILE_JS}"
      echo "gpu_thermal_status temp patch applied (DSM 7.4 formatGpuInfo)"
    else
      echo "WARN: gpu_thermal_status — formatGpuInfo pattern not found; patch skipped"
    fi
  fi

  # ── PCIe slot device name ───────────────────────────────────────────────────
  # formatExternalDeviceInfo() renders an occupied+recognized PCIe slot as
  # "Synology <cardName>". We inject the real device name into cardName, so drop
  # the hardcoded "Synology " prefix to show the bare device name (format A).
  if grep -qF '`Synology ${r.cardName}`' "${FILE_JS}"; then
    sed -i 's#`Synology ${r.cardName}`#`${r.cardName}`#g' "${FILE_JS}"
    echo "pcie_slot cardName prefix patch applied (drop 'Synology ')"
  else
    echo "WARN: pcie_slot — 'Synology \${r.cardName}' pattern not found; patch skipped"
  fi

  # ── CPU temperature ─────────────────────────────────────────────────────────
  # The minified variable carrying the system uptime string differs by DSM build
  # (observed: 's' with GPU section, 'n' without). Detect it dynamically so a
  # single code path covers both.
  _CPUVAR=$(grep -oE ',t,i,[a-z]\)' "${FILE_JS}" | head -1 | sed 's/.*,//; s/)//')
  if [ -n "${_CPUVAR}" ]; then
    sed -i "s/,t,i,${_CPUVAR})}/,t,i,e.sys_temp?${_CPUVAR}+\" | \"+this.renderTempFromC(e.sys_temp):${_CPUVAR})}/g" "${FILE_JS}"
    echo "sys_temp patch applied (var=${_CPUVAR})"
  else
    echo "WARN: sys_temp — pattern ',t,i,X)' not found in ${FILE_JS}; patch skipped"
  fi

  # ── Fan RPM ─────────────────────────────────────────────────────────────────
  # Same minification variation as CPU temp ('n' or 's'). Write the sed script
  # to a temp file to avoid backtick/dollar-sign escaping in the shell.
  _FANVAR=$(grep -oE '"rcpower",[a-z]\)' "${FILE_JS}" | head -1 | sed 's/.*,//; s/)//')
  if [ -n "${_FANVAR}" ]; then
    _FV="${_FANVAR}"
    cat >/tmp/_cpuinfo_fan_patch.sed <<SEDEOF
s/_T("rcpower",${_FV}),/_T("rcpower", ${_FV})?e.fan_list?_T("rcpower", ${_FV}) + e.fan_list.map(fan => \` | \${fan} RPM\`).join(""):_T("rcpower", ${_FV}):e.fan_list?e.fan_list.map(fan => \`\${fan} RPM\`).join(" | "):_T("rcpower", ${_FV}),/g
SEDEOF
    sed -i -f /tmp/_cpuinfo_fan_patch.sed "${FILE_JS}"
    rm -f /tmp/_cpuinfo_fan_patch.sed
    echo "fan_list patch applied (var=${_FANVAR})"
  else
    echo "WARN: fan_list — pattern '_T(\"rcpower\",X)' not found in ${FILE_JS}; patch skipped"
  fi

  [ -f "${FILE_GZ}.bak" ] && gzip -c "${FILE_JS}" >"${FILE_GZ}"

  if [ "${1}" = "-s" ] || [ ! -f "${PROXY_BIN}" ]; then
    if ps -aux | grep -v grep | grep -q "${PROXY_BIN}" >/dev/null; then
      /usr/bin/pkill -f "${PROXY_BIN}"
    fi
    restore_nginx
    systemctl reload nginx
  else
    # Launch the proxy only if it isn't already running ...
    if ! ps -aux | grep -v grep | grep -q "${PROXY_BIN}" >/dev/null; then
      # nohup + disown to survive shell exit
      nohup "${PROXY_BIN}" >/dev/null 2>&1 &
      PROXY_PID=$!
      disown ${PROXY_PID}
      # Reduce OOM-killer eligibility
      if [ -d "/proc/${PROXY_PID}" ]; then
        echo -1000 > "/proc/${PROXY_PID}/oom_score_adj" 2>/dev/null || true
        renice -n -10 ${PROXY_PID} >/dev/null 2>&1 || true
      fi
    fi
    # ... but always (re)point nginx at the proxy socket. This is idempotent
    # and migration-safe, so it heals an RR leftover (synoscgi_rr.sock) even
    # when the proxy was already up from a previous run.
    repoint_nginx
    systemctl reload nginx
  fi
fi
