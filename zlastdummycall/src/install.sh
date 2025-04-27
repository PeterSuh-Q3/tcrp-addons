#!/usr/bin/env ash
#
# This is free software, licensed under the MIT License.
# See /LICENSE for more information.
#
if [ "${1}" = "patches" ]; then
  echo "Installing addon zlastdummycall - ${1}"
  ash /exts/hdddbonjunior/install.sh modules
  #ash /linuxrc.syno.impl
fi
