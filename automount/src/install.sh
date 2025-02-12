#!/bin/sh

set -e
# 2024.03.13
# Changed to handle only loader partition injection function on HDD,
# and moved the existing checkSynoboot function to the boot-wait addon.

if [ "${1}" = "modules" ]; then

  echo "Installing addon automount - ${1}"

  cp -vf blkid /usr/sbin/blkid
  cp -vf sed /usr/sbin/sed
  cp -vf ethtool /usr/sbin/ethtool
  cp -vf libblkid.so.1 /lib64/libblkid.so.1
  chmod 755 /usr/sbin/ethtool /usr/sbin/blkid /usr/sbin/sed /lib64/libblkid.so.1

elif [ "${1}" = "patches" ]; then

  echo "Installing addon automount - ${1}"

  if [ -b /dev/synoboot1 -a -b /dev/synoboot2 -a -b /dev/synoboot3 ]; then
      echo "Found normal synoboot1 / synoboot2 / synoboot3"
      return
  fi

  devtype="$(blkid | grep "6234-C863" | cut -c 6-7 )"
  if [ "${devtype}" = "sd" ]; then
    partnochk=$(blkid | grep "6234-C863" | sed -E 's#^/dev/sd[a-z]+([0-9]+):.*$#\1#')
    LOADER_DISK=$(blkid | grep "6234-C863" | sed -E 's#^/dev/(sd[a-z]+).*$#\1#')
    echo "Found Normal boot loader on Non Device-Tree model."
  elif [ "${devtype}" = "sa" ]; then
    partnochk=$(blkid | grep "6234-C863" | sed -E 's#^/dev/sata[0-9]+p([0-9]+):.*$#\1#')
    LOADER_DISK=$(blkid | grep "6234-C863" | sed -E 's#^/dev/(sata[0-9]+).*$#\1#')
    echo "Found Normal boot loader on Device-Tree model."
  else
    LOADER_DISK=""
  fi

  if [ -z ${LOADER_DISK} ]; then
    devtype="$(blkid | grep "8765-4321" | cut -c 6-7 )"
    if [ "${devtype}" = "sd" ]; then
      partnochk=$(blkid | grep "8765-4321" | sed -E 's#^/dev/sd[a-z]+([0-9]+):.*$#\1#')
      LOADER_DISK=$(blkid | grep "8765-4321" | sed -E 's#^/dev/(sd[a-z]+).*$#\1#')
      echo "Found SynoDisk Injected boot loader on Non Device-Tree model."
    elif [ "${devtype}" = "sa" ]; then
      partnochk=$(blkid | grep "8765-4321" | sed -E 's#^/dev/sata[0-9]+p([0-9]+):.*$#\1#')
      LOADER_DISK=$(blkid | grep "8765-4321" | sed -E 's#^/dev/(sata[0-9]+).*$#\1#')
      echo "Found SynoDisk Injected boot loader on Device-Tree model."
    else
      LOADER_DISK=""
    fi
  fi  

  if [ -z ${LOADER_DISK} ]; then
    echo "Not Supported Device Type for loader Partition !!!"
    return
  fi

  if [ "${partnochk}" -eq 7 ]; then
    echo "This is SHR Type Disk(Win95 Ext) & Has Syno Boot Partition. $partnochk"  
    p1="4"
    p2="6"
    p3="7"
  else
    p1="1"
    p2="2"
    p3="3"
  fi

  if [ "${devtype}" = "sa" ]; then
    p1="p${p1}"
    p2="p${p2}"
    p3="p${p3}"
  fi

  echo "LOADER_DISK = ${LOADER_DISK}" 

  if [ -d /sys/block/${LOADER_DISK}/${LOADER_DISK}${p3} ]; then
    [ -b /dev/${LOADER_DISK}${p1} ] && ln -s /dev/${LOADER_DISK}${p1} /dev/synoboot1
    [ -b /dev/${LOADER_DISK}${p2} ] && ln -s /dev/${LOADER_DISK}${p2} /dev/synoboot2
    [ -b /dev/${LOADER_DISK}${p3} ] && ln -s /dev/${LOADER_DISK}${p3} /dev/synoboot3
  fi
fi
