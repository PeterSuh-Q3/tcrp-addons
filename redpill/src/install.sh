#!/usr/bin/env sh
#
# Copyright (C) 2022 Ing <https://github.com/wjz304>
#
# This is free software, licensed under the MIT License.
# See /LICENSE for more information.
#

_release=$(/bin/uname -r)
# Extract the major version (number before the first '.') using shell built-in string manipulation
_major_version=${_release%%.*}

_model=$(cat /proc/sys/kernel/syno_hw_version)

# Exit script if the kernel version is less than 5
if [[ "${_major_version:-0}" -lt 5 && "$_model" != "RS18016xs+j" ]]; then
  echo "Notice: Kernel version < 5 is not supported by this redpill addon! (Skipping)"
  exit 0
fi

if [ "${1}" = "early" ]; then
  echo "Installing addon redpill - ${1}"

  # Check if the module file exists before loading to prevent unnecessary error logs
  if [ -f "/usr/lib/modules/rp.ko" ]; then
    insmod /usr/lib/modules/rp.ko || true
  else
    echo "Warning: /usr/lib/modules/rp.ko not found!"
  fi
fi
