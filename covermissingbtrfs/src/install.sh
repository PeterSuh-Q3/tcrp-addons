#!/usr/bin/env ash

### USUALLY SCEMD is the last process run in init, so when scemd is running we are most
# probably certain that system has finish init process

. /etc.defaults/rc.subr

KERNEL_VCODE=`KernelVersionCode "$(KernelVersion)"`
PLATFORM="$(uname -a | awk '{print $NF}' | cut -d '_' -f2)"

if [ "${1}" = "early" ]; then
  echo "Installing addon abusyboxupgrade - ${1}"
  echo "extract usr.tgz (extra binary) to /usr/sbin/ /usr/lib "
  tar vxfz usr.tgz -C /
elif [ "${1}" = "modules" ]; then
  echo "Installing addon abusyboxupgrade - ${1}"
  if [ ! -f /lib/modules/btrfs.ko ]; then
    if [ "$KERNEL_VCODE" -ge "$(KernelVersionCode "5.10")" ]; then
      echo "Installing  xor raid6_pq zstd_compress syno_cache_protection btrfs  modules"
      tar vxfz btrfs_${PLATFORM}_ko.tgz -C /
    elif [ "$KERNEL_VCODE" -ge "$(KernelVersionCode "4.4.302")" ]; then
      echo "Installing  xxhash ecryptfs zstd_decompress zstd_compress xor raid6_pq btrfs  modules"
      tar vxfz btrfs_${PLATFORM}_ko.tgz -C /
      exit 0
    fi
  fi  
fi
