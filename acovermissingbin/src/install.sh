#!/usr/bin/env ash

#
# Copyright (C) 2025-2026 PeterSuh-Q3
# https://github.com/PeterSuh-Q3
#
# This installer script is licensed under the
# PeterSuh-Q3 Non-Commercial Source-Available License.
#
# The kernel module installed by this script is a separate component
# distributed under its applicable GPL-compatible license.
#
### USUALLY SCEMD is the last process run in init, so when scemd is running we are most
# probably certain that system has finish init process
set -e

if [ "${1}" = "early" ]; then
  echo "Installing addon acovermissingbin - ${1}"
  echo "extract usr.tgz (extra binary) to /usr/sbin/ /usr/lib "
  tar vxfz usr.tgz -C / >/dev/null 2>&1
  rm -f /usr/sbin/kmod
  tar vxfz kmod.tgz -C /
  # Provide strings through the statically linked BusyBox binary.
  ln -sf /usr/sbin/busybox-static /usr/sbin/strings
  # Prevent xhci-pci KP when using custom module (NEC USB 3.0 firmware dummy file)
  mkdir -p /lib/firmware
  touch /lib/firmware/renesas_usb_fw.mem
fi

if [ "${1}" = "late" ]; then
  # Stage the static BusyBox in the image root. The symlink target must use
  # the final DSM root path because /tmpRoot is temporary and disappears.
  mkdir -p /tmpRoot/usr/sbin
  cp -f /usr/sbin/busybox-static /tmpRoot/usr/sbin/busybox-static
  chmod 0755 /tmpRoot/usr/sbin/busybox-static
  ln -sf /usr/sbin/busybox-static /tmpRoot/usr/sbin/strings
fi
