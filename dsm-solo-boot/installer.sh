#!/bin/sh

# This script is used by ErrFHOSTDoFdiskFormat
# must specify the install type (-r or/and -d)
# -r: format root partition
# -d: format data partition (only for 1-bay)
. /etc/rc.subr
. /usr/syno/share/environments.sh
. /usr/syno/share/mkfs.sh

SupportHyperConverged=$(GetKV /etc.defaults/synoinfo.conf support_hyper_converged)
IsVDSM=yes
IsAliDSM=yes
InstallableDisks=$(/usr/syno/bin/synodiskport -installable_disk_list)

Sfdisk() { /sbin/sfdisk "$@"; }

ErrorFile="/tmp/installer.error"
Rm -vf "$ErrorFile"

DoOrExit() { # stage cmd...
	local stage="$1"; shift

	Echo "[$stage] $*"

	if "$@"; then
		Echo "[$stage][  ok  ] $*"

	else
		local ret=$?
		Echo "[$stage][failed] $*"
		Echo "$stage:$ret" > "$ErrorFile"
		exit $ret
	fi
}


LINUX_FS_TYPE=83
ROOT_SKIP=8192

#InitVDSMSysDisks
DISKNODE="/dev/sda"

DoOrExit CREATE CreatePartition 5 147456 ${LINUX_FS_TYPE} ${ROOT_SKIP} ${DISKNODE}
dd if=/dev/synoboot1 of=/dev/sda5
DoOrExit CREATE CreatePartition 6 151552 ${LINUX_FS_TYPE} ${ROOT_SKIP} ${DISKNODE}
dd if=/dev/synoboot2 of=/dev/sda6
DoOrExit CREATE CreatePartition 7 8087552 ${LINUX_FS_TYPE} ${ROOT_SKIP} ${DISKNODE}
dd if=/dev/synoboot3 of=/dev/sda7

# boot on to /dev/sda5
echo -e "a\n5\nw" | fdisk /dev/sda

# We will write root compatible bit on DSM7.1
# Before that, we can only reset it to default
#DoOrExit RESETROOTCOMPATIBLEBIT /usr/syno/sbin/reset_root_compatiblie_bit.sh

#if [ "static" = "$DiskSwap" ]; then
#    DoOrExit MKSWAP /sbin/mkswap "$SwapPartition"
#fi

# Ext4 rootfs
#DoOrExit MKFS MakeFS "ext4" "$RootPartition"

#Mount "$RootPartition" /mnt
#/bin/touch /mnt/.noroot
#Umount /mnt

#if [ -x /usr/syno/bin/mantool ]; then
#	/usr/syno/bin/mantool -auto_poweron_disable
#fi

exit 0
