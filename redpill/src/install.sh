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

# Read DSM major.minor version from /etc.defaults/VERSION
# The file uses key="value" shell-compatible syntax (majorversion="7" minorversion="3")
# so awk with " as field separator extracts the unquoted numeric value.
_dsm_major=$(awk -F'"' '/^majorversion=/{print $2; exit}' /etc.defaults/VERSION 2>/dev/null)
_dsm_minor=$(awk -F'"' '/^minorversion=/{print $2; exit}' /etc.defaults/VERSION 2>/dev/null)
_dsm_major=${_dsm_major:-0}
_dsm_minor=${_dsm_minor:-0}

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

  # Locate rp.ko. On kernel 5 it's pre-placed at /usr/lib/modules/rp.ko by the
  # bootloader. On kernel 3/4 the bootloader stages it at /addons/rp.ko, so we
  # copy it into /lib/modules/ first to load from a stable location.
  _rp_ko=""
  for _p in /usr/lib/modules/rp.ko /lib/modules/rp.ko; do
    [ -f "$_p" ] && _rp_ko="$_p" && break
  done

  if [ -z "$_rp_ko" ] && [ -f /addons/rp.ko ]; then
    echo "  Staging /addons/rp.ko -> /lib/modules/rp.ko"
    mkdir -p /lib/modules
    cp -f /addons/rp.ko /lib/modules/rp.ko \
      && _rp_ko=/lib/modules/rp.ko
  fi

  if [ -n "$_rp_ko" ] && [ -f "$_rp_ko" ]; then
    echo "  Loading $_rp_ko"
    insmod "$_rp_ko" || { echo "redpill load failed: $(dmesg | tail -5)"; true; }
  else
    echo "Warning: rp.ko not found (checked /usr/lib/modules/, /lib/modules/, /addons/)"
  fi
fi
