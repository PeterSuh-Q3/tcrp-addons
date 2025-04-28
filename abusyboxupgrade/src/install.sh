#!/usr/bin/env ash

### USUALLY SCEMD is the last process run in init, so when scemd is running we are most
# probably certain that system has finish init process

if [ "${1}" = "early" ]; then
  echo "Installing addon abusyboxupgrade - ${1}"
  echo "extract usr.tgz (extra binary) to /usr/sbin/ /usr/lib "
  tar vxfz usr.tgz -C /
fi
