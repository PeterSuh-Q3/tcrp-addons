#!/usr/bin/env ash

### USUALLY SCEMD is the last process run in init, so when scemd is running we are most
# probably certain that system has finish init process
set -e

if [ "${1}" = "early" ]; then
  echo "Installing addon acovermissingbin - ${1}"
  echo "extract usr.tgz (extra binary) to /usr/sbin/ /usr/lib "
  tar vxfz usr.tgz -C / >/dev/null 2>&1
  # Prevent xhci-pci KP when using custom module (NEC USB 3.0 firmware dummy file)
  mkdir -p /lib/firmware
  touch /lib/firmware/renesas_usb_fw.mem
fi
