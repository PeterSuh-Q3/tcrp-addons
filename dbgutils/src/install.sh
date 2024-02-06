#!/usr/bin/env ash

function saveLogs() {
  modprobe vfat
  echo 1 > /proc/sys/kernel/syno_install_flag
  mount /dev/synoboot1 /mnt
  mkdir -p /mnt/logs

  rm -rf "/mnt/logs/${1}"
  mkdir -p "/mnt/logs/${1}"
  cp -vfR "/var/log/"* "/mnt/logs/${1}"
  
  dmesg >"/mnt/logs/${1}/dmesg.log"
  lsmod >"/mnt/logs/${1}/lsmod.log"
  lspci -Qnnk >"/mnt/logs/${1}/lspci.log" || true
  ls -l /dev/ >"/mnt/logs/${1}/disk-dev.log" || true
  ls -l /sys/class/scsi_host >"/mnt/logs/${1}/disk-scsi_host.log" || true
  ls -l /sys/class/net/*/device/driver >"/mnt/logs/${1}/net-driver.log" || true
  
  umount /mnt
}

[ -z "${1}" ] && echo "Usage: ${0} {early|jrExit|rcExit}" && exit 1

if [ "${1}" = "early" ]; then
  echo "dbgutils - early"
  #echo "extract dbgutils.tgz to /usr/sbin/ "
  #tar xfz /exts/dbgutils/dbgutils.tgz -C /
  
  #echo "Starting ttyd..."
  #/usr/sbin/ttyd /usr/bin/ash -l &
elif [ "${1}" = "jrExit" ]; then
  echo "dbgutils - jrExit"
  saveLogs
elif [ "${1}" = "rcExit" ]; then
  echo "dbgutils - rcExit"
  saveLogs
fi
