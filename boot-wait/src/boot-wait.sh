#!/bin/sh

# 2024.03.13
# Changer : PeterSuh-Q3
# Change from node creation method to symbolic link creation method

dump_all_partitions()
{
  echo ""
  echo "========== BEGIN DUMP OF ALL PARTITIONS DETECTED ==========="
  /usr/sbin/sfdisk -l
  echo "========== END OF DUMP OF ALL PARTITIONS DETECTED =========="
}

# synoboot
function checkSynoboot() {

    for devtype in $(fdisk -l | grep "Disk /dev/" | cut -c 11-12 ); do

      if [ "${devtype}" = "sd" ]; then
        BOOTDISK="$(blkid | grep "6234-C863" | grep "/dev/${devtype}" | cut -c 6-8 )"
        echo "Found USB or HDD Disk loader!"
      elif [ "${devtype}" = "us" ]; then
        BOOTDISK="$(blkid | grep "6234-C863" | grep "/dev/${devtype}" | cut -c 6-9 )"
        echo "Found USB Disk loader!"
      elif [ "${devtype}" = "sa" ]; then
        BOOTDISK="$(blkid | grep "6234-C863" | grep "/dev/${devtype}" | cut -c 6-10 )"
        echo "Found Sata Disk loader!"
      elif [ "${devtype}" = "nv" ]; then
        BOOTDISK="$(blkid | grep "6234-C863" | grep "/dev/${devtype}" | cut -c 6-12 )"
        echo "Found NVMe Disk loader!"
      elif [ "${devtype}" = "mm" ]; then
        BOOTDISK="$(blkid | grep "6234-C863" | grep "/dev/${devtype}" | cut -c 6-12 )"
        echo "Found MMC Disk loader!"
      else
        BOOTDISK=""
        echo "BOOTDISK value is empty or USB Stick Found!"
        continue
      fi

      if [ $(fdisk -l | grep "83 Linux" | grep "/dev/${BOOTDISK}" | wc -l ) -eq 3 ]; then
        echo "USB Stick or vmdk bootloader disk Found!"
      else
        continue
      fi

      if [ "${devtype}" = "sd" ]; then
        p1="1"
        p2="2"
        p3="3"
      else
        p1="p1"
        p2="p2"
        p3="p3"
      fi

      if [ -b /dev/synoboot1 -a -b /dev/synoboot2 -a -b /dev/synoboot3 ]; then
        echo "Found synoboot1 / synoboot2 / synoboot3"
        return
      fi
      
      # usbN, sdN, sataN, nvmeN
      if [ ! -b /dev/synoboot1 -a -b /dev/${BOOTDISK}${p1} ]; then
        echo "synoboot1 Not Found, Make symbolic link"
        ln -s /dev/${BOOTDISK}${p1} /dev/synoboot1
      fi
      if [ ! -b /dev/synoboot2 -a -b /dev/${BOOTDISK}${p2} ]; then
        echo "synoboot2 Not Found, Make symbolic link"
        ln -s /dev/${BOOTDISK}${p2} /dev/synoboot2
      fi
      if [ ! -b /dev/synoboot3 -a -b /dev/${BOOTDISK}${p3} ]; then
        echo "synoboot3 Not Found, Make symbolic link"
        ln -s /dev/${BOOTDISK}${p3} /dev/synoboot3
      fi
      rm -vf /dev/${BOOTDISK}
      touch /.bootdisk
      echo "${BOOTDISK}" > /.bootdisk
      echo "${p1}" > /.p1
      echo "${p2}" > /.p2
      echo "${p3}" > /.p3
    done

}

if [ "${1}" = "modules" ]; then

  cp -vf blkid /usr/sbin/blkid
  cp -vf sed /usr/sbin/sed
  cp -vf libblkid.so.1 /lib64/libblkid.so.1
  chmod 755 /usr/sbin/blkid /usr/sbin/sed /lib64/libblkid.so.1

elif [ "${1}" = "patches" ]; then
    wait_time=10 # maximum wait time in seconds

    time_counter=0
    while [ ! -b /dev/synoboot1 ] && [ $time_counter -lt $wait_time ]; do
      sleep 1
      echo "Still waiting for synoboot device (waited $((time_counter=time_counter+1)) of ${wait_time} seconds)"
    done

    if [ ! -b /dev/synoboot1 ]; then
      touch /.no_synoboot
      echo "ERROR: Timeout waiting for /dev/synoboot device to appear."
      echo "Most likely your vid/pid configuration is not correct, or you don't have drivers needed for your USB/SATA controller"
      dump_all_partitions
      echo "Force the creation of synoboot1, synoboot2 and synoboot3 symbolic links..."
      checkSynoboot
      echo "Confirmed a valid-looking /dev/synoboot1, 2 and 3 device"
      exit 0
    fi

    if [ ! -b /dev/synoboot1 ] || [ ! -b /dev/synoboot2 ]; then
      echo "The /dev/synoboot device exists but it does not contain expected partitions (>=2 partitions)"
      dump_all_partitions
      exit 1
    fi
fi
