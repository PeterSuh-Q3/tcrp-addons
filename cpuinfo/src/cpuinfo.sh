#!/usr/bin/env bash
#
# Copyright (C) 2022 Ing <https://github.com/wjz304>
#
# This is free software, licensed under the MIT License.
# See /LICENSE for more information.
#

FILE_JS="/usr/syno/synoman/webman/modules/AdminCenter/admin_center.js"
FILE_GZ="${FILE_JS}.gz"

if [ ! -f "${FILE_JS}" ] && [ ! -f "${FILE_GZ}" ]; then
  echo "File ${FILE_JS} does not exist"
  exit 0
fi

if [ "${1}" = "-r" ]; then
  if [ -f "${FILE_GZ}.bak" ]; then
    rm -f "${FILE_JS}" "${FILE_GZ}"
    mv -f "${FILE_GZ}.bak" "${FILE_GZ}"
    gzip -dc "${FILE_GZ}" >"${FILE_JS}"
  elif [ -f "${FILE_JS}.bak" ]; then
    mv -f "${FILE_JS}.bak" "${FILE_JS}"
  fi
  if ps -aux | grep -v grep | grep -q "/usr/sbin/synoscgiproxy" >/dev/null; then
    /usr/bin/pkill -f "/usr/sbin/synoscgiproxy"
  fi
  [ -f "/etc/nginx/nginx.conf.bak" ] && mv -f /etc/nginx/nginx.conf.bak /etc/nginx/nginx.conf
  [ -f "/usr/syno/share/nginx/nginx.mustache.bak" ] && mv -f /usr/syno/share/nginx/nginx.mustache.bak /usr/syno/share/nginx/nginx.mustache
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
  if [ "${1}" = "-s" ] || [ ! -f "/usr/sbin/synoscgiproxy" ]; then
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

    CARDN=$(ls -d /sys/class/drm/card* 2>/dev/null | head -1)
    if [ -d "${CARDN}" ]; then
      PCIDN="$(awk -F= '/PCI_SLOT_NAME/ {print $2}' "${CARDN}/device/uevent" 2>/dev/null)"
      lspci -nnQ
      LNAME="$(lspci -s ${PCIDN:-"99:99.9"} 2>/dev/null | sed "s/.*: //")"
      # LABLE="$(cat "/sys/class/drm/card0/device/label" 2>/dev/null)"
      CLOCK="$(cat "${CARDN}/gt_max_freq_mhz" 2>/dev/null) MHz"
      MEMORY="$(awk '{s=(strtonum($2)-strtonum($1)+1)/1048576} (and(strtonum($3),0x200))&&(and(strtonum($3),0x2000))&&(and(strtonum($3),0x40000))&&s>0{print int(s) " MiB"; exit}' "${CARDN}/device/resource" 2>/dev/null)"
      if [ -n "${LNAME}" ] && [ -n "${CLOCK}" ] && [ -n "${MEMORY}" ]; then
        echo "GPU Info set to: \"${LNAME}\" \"${CLOCK}\" \"${MEMORY}\""
        # t.gpu={};t.gpu.clock=\"455 MHz\";t.gpu.memory=\"8192 MiB\";t.gpu.name=\"Tesla P4\";t.gpu.temperature_c=47;t.gpu.tempwarn=false;
        #sed -i "s/t=this.getActiveApi(t);let/t=this.getActiveApi(t);if(!t.gpu){t.gpu={};t.gpu.clock=\"${CLOCK}\";t.gpu.memory=\"${MEMORY}\";t.gpu.name=\"${LNAME}\";}let/g" "${FILE_JS}"
        sed -i 's|t=this.getActiveApi(t);let|t=this.getActiveApi(t);if(!t.gpu){t.gpu={};t.gpu.clock="'"${CLOCK}"'";t.gpu.memory="'"${MEMORY}"'";t.gpu.name="'"${LNAME}"'";}let|g' "${FILE_JS}"
      fi
    fi
  fi
  sed -i "s/_D(\"support_nvidia_gpu\")},/_D(\"support_nvidia_gpu\")||true},/g" "${FILE_JS}"
  sed -i 's/,t,i,s)}/,t,i,e.sys_temp?s+" \| "+this.renderTempFromC(e.sys_temp):s)}/g' "${FILE_JS}"
  sed -i 's/,C,D);/,C,t.gpu.temperature_c?D+" \| "+this.renderTempFromC(t.gpu.temperature_c):D);/g' "${FILE_JS}"
  sed -i 's/_T("rcpower",n),/_T("rcpower", n)?e.fan_list?_T("rcpower", n) + e.fan_list.map(fan => ` | ${fan} RPM`).join(""):_T("rcpower", n):e.fan_list?e.fan_list.map(fan => `${fan} RPM`).join(" | "):_T("rcpower", n),/g' "${FILE_JS}"

  # sed -i 's/(d.push([_T("status","status_version"),t.firmware_ver,f]);)/\1d.push(["bootloader",t.bootloader_ver,f]);/g' "${FILE_JS}"

  [ -f "${FILE_GZ}.bak" ] && gzip -c "${FILE_JS}" >"${FILE_GZ}"

  if [ "${1}" = "-s" ] || [ ! -f "/usr/sbin/synoscgiproxy" ]; then
    if ps -aux | grep -v grep | grep -q "/usr/sbin/synoscgiproxy" >/dev/null; then
      /usr/bin/pkill -f "/usr/sbin/synoscgiproxy"
    fi
    [ -f "/etc/nginx/nginx.conf.bak" ] && mv -f /etc/nginx/nginx.conf.bak /etc/nginx/nginx.conf
    [ -f "/usr/syno/share/nginx/nginx.mustache.bak" ] && mv -f /usr/syno/share/nginx/nginx.mustache.bak /usr/syno/share/nginx/nginx.mustache
    systemctl reload nginx
  else
    if ! ps -aux | grep -v grep | grep -q "/usr/sbin/synoscgiproxy" >/dev/null; then
      # 使用 nohup 和 disown 防止进程被杀死
      nohup "/usr/sbin/synoscgiproxy" >/dev/null 2>&1 &
      PROXY_PID=$!
      disown ${PROXY_PID}
      # 设置进程优先级，降低被 OOM killer 杀死的概率
      if [ -d "/proc/${PROXY_PID}" ]; then
        echo -1000 > "/proc/${PROXY_PID}/oom_score_adj" 2>/dev/null || true
        renice -n -10 ${PROXY_PID} >/dev/null 2>&1 || true
      fi
      [ ! -f "/etc/nginx/nginx.conf.bak" ] && cp -pf /etc/nginx/nginx.conf /etc/nginx/nginx.conf.bak
      sed -i 's|/run/synoscgi.sock;|/run/synoscgi_rr.sock;|' /etc/nginx/nginx.conf
      [ ! -f "/usr/syno/share/nginx/nginx.mustache.bak" ] && cp -pf /usr/syno/share/nginx/nginx.mustache /usr/syno/share/nginx/nginx.mustache.bak
      sed -i 's|/run/synoscgi.sock;|/run/synoscgi_rr.sock;|' /usr/syno/share/nginx/nginx.mustache
      systemctl reload nginx
    fi
  fi
fi
