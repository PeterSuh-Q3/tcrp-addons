#!/usr/bin/env ash

### USUALLY SCEMD is the last process run in init, so when scemd is running we are most
# probably certain that system has finish init process

if [ "${1}" = "modules" ]; then
  echo "Installing addon abusyboxupgrade - ${1}"
  echo "extract usr-busybox.tgz (busybox 1.35.0) to /usr/sbin/ "
  tar vxfz usr-busybox.tgz -C /usr/sbin/
  mv /usr/sbin/busybox /usr/sbin/busybox135
  echo "make syboliclink for new busybox 1.35.0 "
  /usr/sbin/busybox135 --install -s /usr/sbin
fi
