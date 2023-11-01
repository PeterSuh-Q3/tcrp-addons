#!/bin/sh

dump_all_partitions()
{
  echo ""
  echo "========== BEGIN DUMP OF ALL PARTITIONS DETECTED ==========="
  /usr/sbin/sfdisk -l
  echo "========== END OF DUMP OF ALL PARTITIONS DETECTED =========="
}

# synoboot
function checkSynoboot() {

  devtype="$(blkid | grep "6234-C863" | cut -c 6-7 )"
  if [ "${devtype}" = "sd" ]; then
    BOOTDISK="$(blkid | grep "6234-C863" | cut -c 6-8 )"
  elif [ "${devtype}" = "sa" ]; then
    BOOTDISK="$(blkid | grep "6234-C863" | cut -c 6-10 )"
  elif [ "${devtype}" = "nv" ]; then
    BOOTDISK="$(blkid | grep "6234-C863" | cut -c 6-10 )"
  fi

  [ -b /dev/synoboot -a -b /dev/synoboot1 -a -b /dev/synoboot2 ] && return
  [ -z "${BOOTDISK}" ] && return

  [ ! -b /dev/synoboot -a -d /sys/block/${BOOTDISK} ] &&
    /bin/mknod /dev/synoboot b $(cat /sys/block/${BOOTDISK}/dev | sed 's/:/ /') >/dev/null 2>&1
  # sataN, nvmeN
  [ ! -b /dev/synoboot1 -a -d /sys/block/${BOOTDISK}/${BOOTDISK}p1 ] &&
    /bin/mknod /dev/synoboot1 b $(cat /sys/block/${BOOTDISK}/${BOOTDISK}p1/dev | sed 's/:/ /') >/dev/null 2>&1
  [ ! -b /dev/synoboot2 -a -d /sys/block/${BOOTDISK}/${BOOTDISK}p2 ] &&
    /bin/mknod /dev/synoboot2 b $(cat /sys/block/${BOOTDISK}/${BOOTDISK}p2/dev | sed 's/:/ /') >/dev/null 2>&1
  # sdN
  [ ! -b /dev/synoboot1 -a -d /sys/block/${BOOTDISK}/${BOOTDISK}1 ] &&
    /bin/mknod /dev/synoboot1 b $(cat /sys/block/${BOOTDISK}/${BOOTDISK}1/dev | sed 's/:/ /') >/dev/null 2>&1
  [ ! -b /dev/synoboot2 -a -d /sys/block/${BOOTDISK}/${BOOTDISK}2 ] &&
    /bin/mknod /dev/synoboot2 b $(cat /sys/block/${BOOTDISK}/${BOOTDISK}2/dev | sed 's/:/ /') >/dev/null 2>&1

}

if [ "${1}" = "modules" ]; then

  cp -vf blkid /usr/sbin/blkid
  cp -vf sed /usr/sbin/sed
  cp -vf libblkid.so.1 /lib64/libblkid.so.1
  chmod 755 /usr/sbin/blkid /usr/sbin/sed /lib64/libblkid.so.1

elif [ "${1}" = "patches" ]; then
    wait_time=10 # maximum wait time in seconds

    time_counter=0
    while [ ! -b /dev/synoboot ] && [ $time_counter -lt $wait_time ]; do
      sleep 1
      echo "Still waiting for boot device (waited $((time_counter=time_counter+1)) of ${wait_time} seconds)"
    done

    if [ ! -b /dev/synoboot ]; then
      touch /.no_synoboot
      echo "ERROR: Timeout waiting for /dev/synoboot device to appear."
      echo "Most likely your vid/pid configuration is not correct, or you don't have drivers needed for your USB/SATA controller"
      dump_all_partitions
      echo "Force the creation of synoboot, synoboot1 and synoboot2 nodes..."
      checkSynoboot
      echo "Confirmed a valid-looking /dev/synoboot device"
      exit 0
    fi

    [ -b /dev/synoboot3 ] || sleep 1 # sometimes we can hit synoboot but before partscan
    if [ ! -b /dev/synoboot1 ] || [ ! -b /dev/synoboot2 ] || [ ! -b /dev/synoboot3 ]; then
      echo "The /dev/synoboot device exists but it does not contain expected partitions (>=3 partitions)"
      dump_all_partitions
      exit 1
    fi
fi
