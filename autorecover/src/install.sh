#!/usr/bin/env ash

if [ "${1}" = "rcExit" ]; then
  echo "autorecover - ${1}"
  if [ $(cat /var/log/linuxrc.syno.log | grep smallfixnumber | wc -l) -gt 0 ] && [ $(cat /var/log/junior_reason | grep -e error -e [7] | wc -l) -gt 0 ]; then
    echo "smallfixnumber difference detected. Automatic patching is performed. !!!"
    echo "Mount /dev/md0 to /tmpRoot and copy the rd.gz and zImage files."
    mkdir -p /mnt/p2
    cd /dev
    mount -t vfat synoboot2 /mnt/p2
    mkdir /tmpRoot
    mount /dev/md0 /tmpRoot
    cp -vf /tmpRoot/.syno/patch/rd.gz /mnt/p2
    cp -vf /tmpRoot/.syno/patch/zImage /mnt/p2
    cp -vf /tmpRoot/.syno/patch/grub_cksum.syno /mnt/p2
    echo "The copy process is complete, Reboot Now..."
  fi
fi
