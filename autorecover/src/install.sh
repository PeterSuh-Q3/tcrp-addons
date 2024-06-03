#!/usr/bin/env ash

if [ "${1}" = "rcExit" ]; then
  echo "autorecover - ${1}"
  if [ $(cat /var/log/linuxrc.syno.log | grep smallfixnumber | wc -l) -gt 0 ] && [ $(cat /var/log/junior_reason | grep -e error -e [7] | wc -l) -gt 0 ]; then
    echo "smallfixnumber difference detected. Automatic patching is performed. !!!"
    echo "Copy the rd.gz and zImage files from /tmpRoot where /dev/md0 is mounted."
    mkdir -p /mnt/p2
    cd /dev
    mount -t vfat synoboot2 /mnt/p2
    wait_time=10 # maximum wait time in seconds
    time_counter=0
    while [ ! -d /tmpRoot ] && [ $time_counter -lt $wait_time ]; do
      sleep 1
      echo "Still waiting for /tmpRoot Unmounted and Removed (waited $((time_counter=time_counter+1)) of ${wait_time} seconds)"
    done    
    mkdir /tmpRoot
    mount /dev/md0 /tmpRoot
    cp -vf /tmpRoot/.syno/patch/rd.gz /mnt/p2
    cp -vf /tmpRoot/.syno/patch/zImage /mnt/p2
    cp -vf /tmpRoot/.syno/patch/grub_cksum.syno /mnt/p2
    echo "The copy process is complete, Reboot Now..."
    #reboot
  fi
fi
