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

if [ ! -f "${FILE_JS}" ] && [ ! -f "${FILE_GZ}" ]; then
  echo "File ${FILE_JS} does not exist"
  exit 0
fi

if [ "${1}" = "-r" ]; then
  rm -f "${GPU_INFO_FILE}"
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
  # leaves stale gpu_info for the proxy to inject.
  rm -f "${GPU_INFO_FILE}"

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
    GCLOCK="0 MHz"
    [ -f "${CARDN}/gt_max_freq_mhz" ] && GCLOCK="$(cat "${CARDN}/gt_max_freq_mhz" 2>/dev/null) MHz"
    [ -f "${CARDN}/device/pp_dpm_sclk" ] && GCLOCK="$(cat "${CARDN}/device/pp_dpm_sclk" 2>/dev/null | grep '\*' | awk '{print $2}') MHz"
    GMEM="$(awk '{s=(strtonum($2)-strtonum($1)+1)/1048576} (and(strtonum($3),0x200))&&(and(strtonum($3),0x2000))&&(and(strtonum($3),0x40000))&&s>0{print int(s) " MiB"; exit}' "${CARDN}/device/resource" 2>/dev/null)"
    [ -n "${GNAME}" ] && [ -n "${GCLOCK}" ] && [ -n "${GMEM}" ] || continue
    [ -z "${FIRST_NAME}" ] && { FIRST_NAME="${GNAME}"; FIRST_CLOCK="${GCLOCK}"; FIRST_MEMORY="${GMEM}"; }
    echo "GPU Info (drm) set to: \"${GNAME}\" \"${GCLOCK}\" \"${GMEM}\""
    _append_gpu "$(printf '{"name":"%s","status":"compatible","clock":"%s","memory":"%s","built_in_gpu_slot_num":0}' \
      "$(_json_escape "${GNAME}")" "${GCLOCK}" "${GMEM}")"
  done

  # 2. NVIDIA via nvidia-smi (proprietary driver). One row per GPU:
  #    name, max graphics clock (MHz), total memory (MiB), temperature (C).
  if command -v nvidia-smi >/dev/null 2>&1 && ls /dev/nvidia[0-9]* >/dev/null 2>&1; then
    while IFS=, read -r NVN NVC NVM NVT; do
      NVN="$(printf '%s' "${NVN}" | sed 's/^ *//; s/ *$//')"
      NVC="$(printf '%s' "${NVC}" | tr -dc '0-9')"
      NVM="$(printf '%s' "${NVM}" | tr -dc '0-9')"
      NVT="$(printf '%s' "${NVT}" | tr -dc '0-9')"
      [ -n "${NVN}" ] || continue
      NVNAME="NVIDIA ${NVN}"; NVCLOCK="${NVC:-0} MHz"; NVMEM="${NVM:-0} MiB"
      [ -z "${FIRST_NAME}" ] && { FIRST_NAME="${NVNAME}"; FIRST_CLOCK="${NVCLOCK}"; FIRST_MEMORY="${NVMEM}"; }
      echo "GPU Info (nvidia) set to: \"${NVNAME}\" \"${NVCLOCK}\" \"${NVMEM}\" ${NVT:-?}C"
      # temperature_c + tempwarn (both must be defined for the temp row to render).
      if [ -n "${NVT}" ]; then
        _append_gpu "$(printf '{"name":"%s","status":"compatible","clock":"%s","memory":"%s","temperature_c":%s,"tempwarn":false,"built_in_gpu_slot_num":0}' \
          "$(_json_escape "${NVNAME}")" "${NVCLOCK}" "${NVMEM}" "${NVT}")"
      else
        _append_gpu "$(printf '{"name":"%s","status":"compatible","clock":"%s","memory":"%s","built_in_gpu_slot_num":0}' \
          "$(_json_escape "${NVNAME}")" "${NVCLOCK}" "${NVMEM}")"
      fi
    done < <(nvidia-smi --query-gpu=name,clocks.max.graphics,memory.total,temperature.gpu --format=csv,noheader,nounits 2>/dev/null)
  fi

  if [ -n "${GPU_ELEMS}" ]; then
    # DSM <= 7.3 path: inject the first GPU as the t.gpu object client-side
    # (gated by the support_nvidia_gpu||true patch below).
    sed -i 's|t=this.getActiveApi(t);let|t=this.getActiveApi(t);if(!t.gpu){t.gpu={};t.gpu.clock="'"${FIRST_CLOCK}"'";t.gpu.memory="'"${FIRST_MEMORY}"'";t.gpu.name="'"${FIRST_NAME}"'";}let|g' "${FILE_JS}"
    # DSM 7.4 path: hand the gpu_info[] array to the proxy (see GPU_INFO_FILE).
    printf '[%s]\n' "${GPU_ELEMS}" >"${GPU_INFO_FILE}"
  fi

  sed -i "s/_D(\"support_nvidia_gpu\")},/_D(\"support_nvidia_gpu\")||true},/g" "${FILE_JS}"
  sed -i 's/,t,i,s)}/,t,i,e.sys_temp?s+" \| "+this.renderTempFromC(e.sys_temp):s)}/g' "${FILE_JS}"
  sed -i 's/,C,D);/,C,t.gpu.temperature_c?D+" \| "+this.renderTempFromC(t.gpu.temperature_c):D);/g' "${FILE_JS}"
  sed -i 's/_T("rcpower",n),/_T("rcpower", n)?e.fan_list?_T("rcpower", n) + e.fan_list.map(fan => ` | ${fan} RPM`).join(""):_T("rcpower", n):e.fan_list?e.fan_list.map(fan => `${fan} RPM`).join(" | "):_T("rcpower", n),/g' "${FILE_JS}"

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
