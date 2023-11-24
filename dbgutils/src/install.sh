#!/usr/bin/env ash

function saveLogs() {
  #modprobe vfat
  echo 1 > /proc/sys/kernel/syno_install_flag
  mount /dev/synoboot1 /mnt
  mkdir -p /mnt/logs/jr
  cp /var/log/* /mnt/logs/jr
  dmesg > /mnt/logs/jr/dmesg
  umount /mnt
}

if [ "${1}" = "early" ]; then
  echo "dbgutils - early"
  #echo "extract dbgutils.tgz to /usr/sbin/ "
  #tar xfz /exts/dbgutils/dbgutils.tgz -C /
  
  #echo "Starting ttyd..."
  #/usr/sbin/ttyd /usr/bin/ash -l &
#elif [ "${1}" = "jrExit" ]; then
#  saveLogs
elif [ "${1}" = "rcExit" ]; then
  saveLogs
fi
