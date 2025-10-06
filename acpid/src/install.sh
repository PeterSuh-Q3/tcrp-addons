#!/usr/bin/env sh
#
# Copyright (C) 2022 Ing <https://github.com/wjz304>
#
# This is free software, licensed under the MIT License.
# See /LICENSE for more information.
#

if [ "${1}" = "late" ]; then
  echo "Installing addon acpid - ${1}"

  tar -zxf ./acpid-7.1.tgz -C /tmpRoot/

  if [ -f /usr/lib/modules/button.ko ]; then
    cp -vpf /usr/lib/modules/button.ko /tmpRoot/usr/lib/modules/button.ko
  else
    echo "No button.ko found"
  fi

fi
