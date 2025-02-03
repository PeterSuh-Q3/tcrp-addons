#!/bin/sh

set -e
# 2024.03.13
# Changed to handle only loader partition injection function on HDD,
# and moved the existing checkSynoboot function to the boot-wait addon.

# Function to remap device nodes
function remap_device() {
      local src=$1
      local dest=$2
      [ ! -b "$src" ] && return
      
      local major=$(stat -c %t "$src")
      local minor=$(stat -c %T "$src")
      mknod "$dest" b $((0x${major})) $((0x${minor}))
      rm -f "$src"
}

if [ "${1}" = "modules" ]; then

  echo "Installing addon automount - ${1}"

  cp -vf blkid /usr/sbin/blkid
  cp -vf sed /usr/sbin/sed
  cp -vf ethtool /usr/sbin/ethtool
  cp -vf libblkid.so.1 /lib64/libblkid.so.1
  chmod 755 /usr/sbin/ethtool /usr/sbin/blkid /usr/sbin/sed /lib64/libblkid.so.1

elif [ "${1}" = "patches" ]; then

  echo "Installing addon automount - ${1}"

  # Check if /dev/synoboot6 exists
  if [ -b /dev/synoboot6 ]; then
    # Search for unused sdX
    for letter in {a..z}; do
        [ ! -b "/dev/sd${letter}" ] && NEW_DISK="sd${letter}" && break
    done
    [ -z "${NEW_DISK}" ] && { echo "No available sdX device"; exit 1; }
    
    # Remap base devices
    remap_device "/dev/synoboot" "/dev/${NEW_DISK}"
    for i in {1..3}; do
        remap_device "/dev/synoboot${i}" "/dev/${NEW_DISK}${i}"
    done
    
    # Relocate extended partitions
    for i in {4..6}; do
        target=$((i-3))
        remap_device "/dev/synoboot${i}" "/dev/synoboot${target}"
    done
    
    echo "Remapping completed: synoboot -> ${NEW_DISK}, 4-6 -> 1-3"
    
  fi


  if [ -b /dev/synoboot1 -a -b /dev/synoboot2 -a -b /dev/synoboot3 ]; then
      echo "Found normal synoboot1 / synoboot2 / synoboot3"
      return
  fi

  devtype="$(blkid | grep "6234-C863" | cut -c 6-7 )"
  if [ "${devtype}" = "sd" ]; then
    partnochk=$(blkid | grep "6234-C863" | sed -E 's#^/dev/sd[a-z]+([0-9]+):.*$#\1#')
    [ "${partnochk}" -eq 3 ] && return

    LOADER_DISK=$(blkid | grep "6234-C863" | sed -E 's#^/dev/(sd[a-z]+).*$#\1#')
    echo "Found USB or HDD Disk loader!"
    p1="5"
    p2="6"
    p3="4"
  elif [ "${devtype}" = "sa" ]; then
    partnochk=$(blkid | grep "6234-C863" | sed -E 's#^/dev/sata[0-9]+p([0-9]+):.*$#\1#')
    [ "${partnochk}" -eq 3 ] && return

    LOADER_DISK=$(blkid | grep "6234-C863" | sed -E 's#^/dev/(sata[0-9]+).*$#\1#')
    echo "Found Sata Disk loader!"
    p1="p5"
    p2="p6"
    p3="p4"
  else
    LOADER_DISK=""
  fi
  
  if [ -z ${LOADER_DISK} ]; then
    echo "Not Supported Device Type for loader Partition !!!"
    return
  fi

  BOOT_DISK="${LOADER_DISK}"
  if [ -d /sys/block/${LOADER_DISK}/${LOADER_DISK}${p3} ]; then

    for edisk in $(fdisk -l | grep "Disk /dev/${devtype}" | sed -E 's#^Disk /dev/(sd[a-z]+|sata[0-9]+):.*$#\1#'); do
        if [ $(fdisk -l | grep "fd Linux raid autodetect" | grep ${edisk} | wc -l ) -eq 3 ] && [ $(fdisk -l | grep "83 Linux" | grep ${edisk} | wc -l ) -eq 2 ]; then
            echo "This is BASIC or SHR Type Disk & Has Syno Boot Partition. $edisk"
            BOOT_DISK="${edisk}"
            if [ $(fdisk -l | grep "Win95 Ext" | grep ${edisk} | wc -l ) -eq 1 ]; then
                echo "This is SHR Type Disk(Win95 Ext) & Has Syno Boot Partition. $edisk"
                p1=$(echo ${p1} | sed 's#5#4#')
            fi
        elif [ $(fdisk -l | grep "Linux RAID" | grep ${edisk} | wc -l ) -eq 3 ] && [ $(fdisk -l | grep "83 Linux" | grep ${edisk} | wc -l ) -eq 2 ]; then
            echo "This is Fixed SHR Type Disk & Has Syno Boot Partition. $edisk"
            p1=$(echo ${p1} | sed 's#5#4#')
        fi
    done
  
    if [ "${BOOT_DISK}" = "${LOADER_DISK}" ]; then
        echo "Failed to find boot Partition !!!"
        return
    fi
    
    [ -b /dev/${BOOT_DISK}${p1} ] && ln -s /dev/${BOOT_DISK}${p1} /dev/synoboot1
    [ -b /dev/${BOOT_DISK}${p2} ] && ln -s /dev/${BOOT_DISK}${p2} /dev/synoboot2
    [ -b /dev/${LOADER_DISK}${p3} ] && ln -s /dev/${LOADER_DISK}${p3} /dev/synoboot3
  
  fi

fi
