#!/usr/bin/env sh
#
# Copyright (C) 2022 Ing <https://github.com/wjz304>
#
# This is free software, licensed under the MIT License.
# See /LICENSE for more information.
#

_release=$(/bin/uname -r)
_major_version=${_release%%.*}

_model=$(cat /proc/sys/kernel/syno_hw_version 2>/dev/null)

# Convert running kernel version (e.g. "4.4.59+", "4.4.302+", "5.10.55+") into a
# comparable integer X*1000000 + Y*10000 + Z so we can decide activation by
# specific kernel ranges instead of major-only.
_kver=$(echo "$_release" | cut -d+ -f1 | cut -d- -f1)
_kver_int=$(echo "$_kver" | awk -F. '{ printf "%d", $1*1000000 + $2*10000 + $3 }')
_lo_int=4040059   # 4.4.59  (apollolake older builds need addon)
_hi_int=5100055   # 5.10.55 (epyc7002 / kernel 5 family always needs addon)

# Activation policy:
#   1) kernel <= 4.4.59           (covers all 3.x and old 4.4.x like apollolake-918+)
#   2) kernel >= 5.10.55          (kernel 5 family)
#   3) model == RS18016xs+-j      (Junior mode special case, preserved)
# DSM version is no longer used to gate.
_allowed=0
if [ "${_kver_int:-0}" -le "${_lo_int}" ]; then
  _allowed=1
elif [ "${_kver_int:-0}" -ge "${_hi_int}" ]; then
  _allowed=1
elif [ "${_model}" = "RS18016xs+-j" ]; then
  _allowed=1
fi

if [ "$_allowed" -eq 0 ]; then
  echo "Notice: kernel ${_kver} not in addon-supported range (<=4.4.59 or >=5.10.55) - skipping"
  exit 0
fi

if [ "${1}" = "early" ]; then
  echo "Installing addon redpill - ${1}"

  # Handle case where redpill was already loaded by rd.gz auto-load.
  # - kernel >= 5 : safe to rmmod and reload with addon's rp.ko
  # - kernel < 5  : rmmod risks kernel panic (verified on k3 RS1219+; treat k4
  #                 the same as a precaution). Accept rd.gz's version and skip.
  if lsmod | grep -q '^redpill '; then
    if [ "${_major_version:-0}" -ge 5 ]; then
      echo "  redpill already loaded - rmmod before reload"
      rmmod redpill 2>/dev/null \
        || echo "  rmmod redpill failed (module may be sealed; will attempt insmod anyway)"
    else
      echo "  redpill already loaded - kernel < 5 rmmod unsafe (panic risk), skipping"
      exit 0
    fi
  fi

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
