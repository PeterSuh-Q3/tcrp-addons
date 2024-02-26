#!/bin/sh

# This script is used by ErrFHOSTDoFdiskFormat
# must specify the install type (-r or/and -d)
# -r: format root partition
# -d: format data partition (only for 1-bay)
. /etc/rc.subr
. /usr/syno/share/environments.sh
. /usr/syno/share/dsmupdate/decide_system_partition.sh
. /usr/syno/share/dsmupdate/decide_data_partition.sh
. /usr/syno/share/get_installable_devices.sh
. /usr/syno/share/mkfs.sh
. /usr/syno/share/synorbd.sh

SupportHyperConverged=$(/bin/get_key_value /etc.defaults/synoinfo.conf support_hyper_converged)
IsVDSM=yes
IsAliDSM=yes
InstallableDisks=$(/usr/syno/bin/synodiskport -installable_disk_list)

Sfdisk() { /sbin/sfdisk "$@"; }
LayoutVer() { /usr/syno/bin/synocheckpartition; echo $?; }

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

SWAP_SIZE=4194304
ROOT_SKIP=8192
SWAP_SKIP=0
LINUX_FS_TYPE=83
LINUX_SWAP_TYPE=82

Umount /volume1
# if not "broadwellntb" or "broadwellntbap"
if [ "$IsUCOrXA" != yes ]; then
	/usr/syno/bin/syno_swap_ctl --off "$SwapPartition"
fi

InitVDSMSysDisks ()
{
	local DISKNODE
	local PARTNO_ROOT
	local PARTNO_SWAP
	local WRITEABLE_SIZE=16777216
	if [ "$IsVDSM" = yes ] && [ "$SupportHyperConverged" = yes ]; then
		WRITEABLE_SIZE=41943040
	fi

	if [ "${IsAliDSM}" = "yes" ]; then
		DISKNODE="/dev/sda"
		PARTNO_ROOT="5"
		PARTNO_SWAP="6"
	else
		if [ "${SupportPortMappingV2}" = "yes" ]; then
			DISKNODE="/dev/sata1"
		else
			DISKNODE="/dev/sda"
		fi
		PARTNO_ROOT="1"
		PARTNO_SWAP="2"
	fi
	for DiskIdx in $InstallableDisks ; do
		if [ "${IsAliDSM}" = "yes" ] && [ "${DiskIdx}" = "sda" ]; then
			continue
		fi

		DoOrExit FDISK Sfdisk -M1 /dev/${DiskIdx}
		DoOrExit CLEAN Sfdisk "--fast-delete" "-1" "/dev/${DiskIdx}"
		#clear synoblock on vdsm
		#if [ "$UniqueRD" = kvmx64 ] || [ "$UniqueRD" = kvmx64sofs ] || [ "$UniqueRD" = kvmx64v2 ]; then
			/bin/dd if=/dev/zero of=/dev/${DiskIdx} bs=512 count=10 seek=1000 > /dev/null 2>&1
		#fi
	done

	if [ "$IsAliDSM" != yes ]; then
		DoOrExit CREATE CreatePartition ${PARTNO_ROOT} ${WRITEABLE_SIZE} ${LINUX_FS_TYPE} ${ROOT_SKIP} ${DISKNODE}
	fi
	DoOrExit CREATE CreatePartition ${PARTNO_SWAP} ${SWAP_SIZE} ${LINUX_SWAP_TYPE} ${SWAP_SKIP} ${DISKNODE}
	Echo "1/1" > /tmp/synodd.sda
}


InitVDSMSysDisks

# We will write root compatible bit on DSM7.1
# Before that, we can only reset it to default
DoOrExit RESETROOTCOMPATIBLEBIT /usr/syno/sbin/reset_root_compatiblie_bit.sh

if [ "static" = "$DiskSwap" ]; then
    DoOrExit MKSWAP /sbin/mkswap "$SwapPartition"
fi

# Ext4 rootfs
DoOrExit MKFS MakeFS "ext4" "$RootPartition"

Mount "$RootPartition" /mnt
/bin/touch /mnt/.noroot
Umount /mnt

#if [ -x /usr/syno/bin/mantool ]; then
#	/usr/syno/bin/mantool -auto_poweron_disable
#fi

exit 0
