#!/usr/bin/env ash

### USUALLY SCEMD is the last process run in init, so when scemd is running we are most
# probably certain that system has finish init process
set -e

REVISION="$(uname -a | cut -d ' ' -f4)"

if [ "${1}" = "early" ]; then
  echo "Installing addon acovermissingbin - ${1}"
  echo "extract usr.tgz (extra binary) to /usr/sbin/ /usr/lib "
  if [ ${REVISION} = "#25556" ]; then
    gunzip -c usr6.tgz | tar xvf - -C /
    cp -vf /usr/sbin/6.2.4/* /usr/sbin/
    cp -vf /usr/lib/6.2.4/* /usr/lib/
    mv -f /usr/lib/loop.ko /usr/lib/modules/loop.ko
    modprobe loop
    lsmod | grep loop
  else
    tar vxfz usr.tgz -C /
  fi  
fi
