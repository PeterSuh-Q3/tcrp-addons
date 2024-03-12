#!/bin/sh

# synoboot
function checkSynoboot() {

  devtype="$(blkid | grep "6234-C863" | cut -c 6-7 )"
  if [ "${devtype}" = "sa" ]; then
    BOOTDISK="$(blkid | grep "6234-C863" | cut -c 6-10 )"
    echo "Found Sata Disk loader!"
  elif [ "${devtype}" = "nv" ]; then
    BOOTDISK="$(blkid | grep "6234-C863" | cut -c 6-12 )"
    echo "Found NVMe Disk loader!"
  elif [ "${devtype}" = "mm" ]; then
    BOOTDISK="$(blkid | grep "6234-C863" | cut -c 6-13 )"
    echo "Found MMC Disk loader!"
  else
    BOOTDISK=""
  fi

  if [ -b /dev/synoboot -a -b /dev/synoboot1 -a -b /dev/synoboot2 ]; then
    echo "Found synoboot / synoboot1 / synoboot2"
    return
  fi
  
  if [ -z "${BOOTDISK}" ]; then
    echo "BOOTDISK value is empty or USB Stick Found!"
    return
  fi

  if [ ! -b /dev/synoboot -a -d /sys/block/${BOOTDISK} ]; then
    echo "synoboot Not Found, Make node"
    /bin/mknod /dev/synoboot b $(cat /sys/block/${BOOTDISK}/dev | sed 's/:/ /') >/dev/null 2>&1
  fi
  # sataN, nvmeN
  if [ ! -b /dev/synoboot1 -a -d /sys/block/${BOOTDISK}/${BOOTDISK}p1 ]; then
    echo "synoboot1 Not Found, Make node"
    /bin/mknod /dev/synoboot1 b $(cat /sys/block/${BOOTDISK}/${BOOTDISK}p1/dev | sed 's/:/ /') >/dev/null 2>&1
  fi
  if [ ! -b /dev/synoboot2 -a -d /sys/block/${BOOTDISK}/${BOOTDISK}p2 ]; then
    echo "synoboot2 Not Found, Make node"
    /bin/mknod /dev/synoboot2 b $(cat /sys/block/${BOOTDISK}/${BOOTDISK}p2/dev | sed 's/:/ /') >/dev/null 2>&1
  fi

}

if [ "${1}" = "modules" ]; then

  cp -vf blkid /usr/sbin/blkid
  cp -vf sed /usr/sbin/sed
  cp -vf libblkid.so.1 /lib64/libblkid.so.1
  chmod 755 /usr/sbin/blkid /usr/sbin/sed /lib64/libblkid.so.1

elif [ "${1}" = "patches" ]; then
  LOADER_DISK=$(blkid | grep "6234-C863" | cut -c 1-8 | awk -F\/ '{print $3}')

  BOOT_DISK="${LOADER_DISK}"
  if [ -d /sys/block/${LOADER_DISK}/${LOADER_DISK}5 ]; then
    for edisk in $(fdisk -l | grep "Disk /dev/sd" | awk '{print $2}' | sed 's/://' ); do
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

    [ -f ${BOOT_DISK}${p1} ] && ln -s /dev/${BOOT_DISK}${p1} /dev/synoboot1
    [ -f ${BOOT_DISK}${p2} ] && ln -s /dev/${BOOT_DISK}${p2} /dev/synoboot2
    [ -f ${LOADER_DISK}${p3} ] && ln -s /dev/${LOADER_DISK}${p3} /dev/synoboot3
  
  fi
  checkSynoboot
fi
