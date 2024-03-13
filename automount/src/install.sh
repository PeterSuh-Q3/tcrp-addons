#!/bin/sh

# 2024.03.13
# Changed to handle only loader partition injection function on HDD,
# and moved the existing checkSynoboot function to the boot-wait addon.

if [ "${1}" = "modules" ]; then

  cp -vf blkid /usr/sbin/blkid
  cp -vf sed /usr/sbin/sed
  cp -vf libblkid.so.1 /lib64/libblkid.so.1
  chmod 755 /usr/sbin/blkid /usr/sbin/sed /lib64/libblkid.so.1

elif [ "${1}" = "patches" ]; then
  LOADER_DISK=$(blkid | grep "6234-C863" | cut -c 6-8 )

  BOOT_DISK="${LOADER_DISK}"
  if [ -d /sys/block/${LOADER_DISK}/${LOADER_DISK}5 ]; then
    for edisk in $(fdisk -l | grep "Disk /dev/sd" | cut -c 6-13 ); do
        if [ $(fdisk -l | grep "fd Linux raid autodetect" | grep ${edisk} | wc -l ) -eq 3 ] && [ $(fdisk -l | grep "83 Linux" | grep ${edisk} | wc -l ) -eq 2 ]; then
            echo "This is BASIC Type Disk & Has Syno Boot Partition. $edisk"
            BOOT_DISK=$(echo "$edisk" | cut -c 6-8)
        fi
    done
    if [ "${BOOT_DISK}" = "${LOADER_DISK}" ]; then
        echo "Failed to find boot Partition on !!!"
        exit 99
    fi
    p1="5"
    p2="6"
    p3="5"

    [ -b /dev/${BOOT_DISK}${p1} ] && ln -s /dev/${BOOT_DISK}${p1} /dev/synoboot1
    [ -b /dev/${BOOT_DISK}${p2} ] && ln -s /dev/${BOOT_DISK}${p2} /dev/synoboot2
    [ -b /dev/${LOADER_DISK}${p3} ] && ln -s /dev/${LOADER_DISK}${p3} /dev/synoboot3
  
  fi

fi
