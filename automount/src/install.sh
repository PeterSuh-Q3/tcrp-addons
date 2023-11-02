#!/bin/sh

# synoboot
function checkSynoboot() {

  devtype="$(blkid | grep "6234-C863" | cut -c 6-7 )"
  if [ "${devtype}" = "sa" ]; then
    BOOTDISK="$(blkid | grep "6234-C863" | cut -c 6-10 )"
    echo "Found Sata Disk loader!"
  elif [ "${devtype}" = "nv" ]; then
    BOOTDISK="$(blkid | grep "6234-C863" | cut -c 6-10 )"
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
  checkSynoboot
fi
