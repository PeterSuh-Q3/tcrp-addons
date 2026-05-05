#!/usr/bin/env sh
#
# Copyright (C) 2022 Ing <https://github.com/wjz304>
#
# This is free software, licensed under the MIT License.
# See /LICENSE for more information.
#

_release=$(/bin/uname -r)
_major_version=${_release%%.*}

_model=$(cat /proc/sys/kernel/syno_hw_version)

# Read DSM major.minor version (e.g., "7.3" from "7.3-12345")
_dsm_version=$(cat /etc.defaults/VERSION 2>/dev/null | awk -F= '/^majorversion/{major=$2} /^minorversion/{minor=$2} END{print major"."minor}')
_dsm_major=${_dsm_version%%.*}
_dsm_minor=${_dsm_version##*.}

# Determine if this environment is allowed to proceed:
# 1) kernel >= 5  (standard support)
# 2) kernel < 5 AND model == RS18016xs+-j  (Junior mode exception)
# 3) kernel < 5 AND DSM 7.3.x              (DSM 7.3 + kernel 3.x exception)
_allowed=0

if [[ "${_major_version:-0}" -ge 5 ]]; then
  _allowed=1
elif [[ "$_model" == "RS18016xs+-j" ]]; then
  _allowed=1
elif [[ "${_dsm_major:-0}" -eq 7 && "${_dsm_minor:-0}" -eq 3 ]]; then
  _allowed=1
fi

if [[ "$_allowed" -eq 0 ]]; then
  echo "Notice: Kernel version < 5 is not supported by this redpill addon! (Skipping)"
  exit 0
fi

if [ "${1}" = "early" ]; then
  echo "Installing addon redpill - ${1}"

  if [ -f "/usr/lib/modules/rp.ko" ]; then
    insmod /usr/lib/modules/rp.ko || { echo "redpill load failed: $(dmesg | tail -5)"; true; }
  else
    echo "Warning: /usr/lib/modules/rp.ko not found!"
  fi
fi
