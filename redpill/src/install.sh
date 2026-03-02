#!/usr/bin/env sh
#
# Copyright (C) 2022 Ing <https://github.com/wjz304>
#
# This is free software, licensed under the MIT License.
# See /LICENSE for more information.
#

_release=$(/bin/uname -r)
if [ "$(/bin/echo ${_release%%[-+]*} | /usr/bin/cut -d'.' -f1)" -lt 5 ]; then
  echo " Kernel version < 5 is not supported redpill addon!"
  exit 0
fi

if [ "${1}" = "early" ]; then
  echo "Installing addon redpill - ${1}"

  insmod /usr/lib/modules/rp.ko
fi
