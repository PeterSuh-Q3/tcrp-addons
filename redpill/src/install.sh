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

  # Detect prior load. STEALTH=NORMAL/FULL builds hide redpill from
  # /proc/modules and possibly /sys/module, so a missing lsmod hit does NOT
  # mean it's actually unloaded. Use a best-effort signal here for the rmmod
  # decision; the insmod step below has its own stealth-aware tolerance.
  _is_loaded=0
  if lsmod | grep -q '^redpill '; then
    _is_loaded=1
  elif [ -d /sys/module/redpill ]; then
    _is_loaded=1
  fi

  if [ "$_is_loaded" -eq 1 ]; then
    # redpill was already loaded (e.g. injected via rd.gz). Do NOT rmmod+reload it.
    # On kernel 5 the reload makes register_fake_sata_boot_shim() run scsi_force_replug()
    # on already-probed SATA disks (remove + rescan), which corrupts the CFS runqueue and
    # panics (rb_erase NULL deref / preempt_count leak). On kernel <5 rmmod is unsafe too.
    # This addon only exists to guarantee a load when rd.gz injection FAILED, so if it's
    # already loaded there is nothing to do.
    echo "  redpill already loaded - keeping existing instance (reload disabled to avoid unload/replug panic)"
    exit 0
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
    _load_out=$(insmod "$_rp_ko" 2>&1)
    _load_rc=$?
    if [ "$_load_rc" -ne 0 ]; then
      # Distinguish stealth-hidden duplicate load (benign) from real failure.
      # busybox insmod prints "File exists" or "Invalid argument"; the kernel
      # log line "redpill: module is already loaded" is the authoritative signal.
      if dmesg | tail -10 | grep -qE "redpill: module is already loaded|File exists"; then
        echo "  redpill appears already loaded (stealth-hidden) - addon insmod no-op accepted"
      else
        echo "  redpill load failed (rc=$_load_rc): $_load_out"
        echo "  recent dmesg: $(dmesg | tail -3)"
      fi
    fi
  else
    echo "Warning: rp.ko not found (checked /usr/lib/modules/, /lib/modules/, /addons/)"
  fi
fi
