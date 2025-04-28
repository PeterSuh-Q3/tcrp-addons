#!/usr/bin/env ash
#
# This is free software, licensed under the MIT License.
# See /LICENSE for more information.
#
if [ "${1}" = "patches" ]; then
  echo "Installing addon zlastdummycall - ${1}"
  cd /exts/hdddbonjunior
  ash /exts/hdddbonjunior/install.sh patches
  #ash /linuxrc.syno.impl
fi
