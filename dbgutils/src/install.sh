#!/usr/bin/env ash

function saveLogs() {
  modprobe vfat
  echo 1 > /proc/sys/kernel/syno_install_flag
  [ ! -b /dev/synoboot1 ] && exit 0

  [ ! -d /mnt/synoboot1 ] && mkdir -p /mnt/synoboot1
  mount /dev/synoboot1 /mnt/synoboot1
  [ $? -ne 0 ] && exit 0
  mkdir -p /mnt/synoboot1/logs

  rm -rf "/mnt/synoboot1/logs/${1}"
  mkdir -p "/mnt/synoboot1/logs/${1}"
  cp -vfR "/var/log/"* "/mnt/synoboot1/logs/${1}"
  
  dmesg >"/mnt/synoboot1/logs/${1}/dmesg.log"
  lsmod >"/mnt/synoboot1/logs/${1}/lsmod.log"
  lspci -Qnnk >"/mnt/synoboot1/logs/${1}/lspci.log" || true
  ls -l /dev/ >"/mnt/synoboot1/logs/${1}/disk-dev.log" || true
  ls -l /sys/class/scsi_host >"/mnt/synoboot1/logs/${1}/disk-scsi_host.log" || true
  ls -l /sys/class/net/*/device/driver >"/mnt/synoboot1/logs/${1}/net-driver.log" || true
  
  umount /mnt/synoboot1
  [ $? -ne 0 ] && exit 0
}

[ -z "${1}" ] && echo "Usage: ${0} {early|jrExit|rcExit}" && exit 1

if [ "${1}" = "early" ]; then
  echo "dbgutils - ${1}"
  #echo "extract dbgutils.tgz to /usr/sbin/ "
  #tar xfz /exts/dbgutils/dbgutils.tgz -C /
  
  #echo "Starting ttyd..."
  #/usr/sbin/ttyd /usr/bin/ash -l &
elif [ "${1}" = "patches" ]; then
  echo "dbgutils - ${1}"
  saveLogs "${1}"
elif [ "${1}" = "rcExit" ]; then
  echo "dbgutils - ${1}"
  saveLogs "${1}"
fi
