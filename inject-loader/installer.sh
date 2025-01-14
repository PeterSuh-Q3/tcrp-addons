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

SupportLocalInstall=$(/bin/get_key_value /etc.defaults/synoinfo.conf support_localinstall)
SupportHyperConverged=$(/bin/get_key_value /etc.defaults/synoinfo.conf support_hyper_converged)
IsVDSM=no
IsHDSeries=no
InstallableDisks=$(/usr/syno/bin/synodiskport -installable_disk_list)

case "$UniqueRD" in
	kvmx64|nextkvmx64|kvmcloud|kvmx64sofs|kvmx64v2)
		IsVDSM=yes
		;;
esac

case "$UniqueModel" in
	hd6500)
		IsHDSeries=yes
		;;
esac

Raidtool() { /sbin/raidtool "$@"; }
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
LINUX_RAID_TYPE="FD"
LINUX_FS_TYPE=83
LINUX_SWAP_TYPE=82

DO_CLEAN_ROOT="no"
DO_CLEAN_DATA="no"
DO_CLEAN_INSTALL="no"
DO_MKFS_ROOT_ONLY="no"

###########################################################

# stop all burn-in test (memtester or DMA test) before install
/usr/sbin/burnin_test -f &> /dev/null

Echo "Check new disk..."
for i; do
	case "${i}" in
		-r)
			DO_CLEAN_ROOT="yes"
			shift
			;;
		-d)
			DO_CLEAN_DATA="yes"
			shift
			;;
		-c)
			DO_CLEAN_INSTALL="yes"
			shift
			;;
		-m)
			# This flag is only for unknown_syno_partition_migration clean install
			DO_MKFS_ROOT_ONLY="yes"
			shift
			;;
	esac
done

Umount /volume1
if [ "$IsUCOrXA" != yes ]; then
	/usr/syno/bin/syno_swap_ctl --off "$SwapPartition"
fi

InitUCXASysDisks ()
{
	local PARTNO_ROOT_TAIPEI="1"
	local PARTNO_PATCH="2"
	local WRITEABLE_SIZE=6291456
	local PATCH_SIZE=3145728
	local PATCH_SKIP=0

	# clean disk & create partition
	/sbin/mdadm -S /dev/md0
	for DiskIdx in $InstallableDisks ; do
		Device=/dev/${DiskIdx}
		DoOrExit FDISK Sfdisk -M1 ${Device}
		DoOrExit CLEAN Sfdisk "--fast-delete" "-1" "${Device}"
		DoOrExit CREATE CreatePartition ${PARTNO_ROOT_TAIPEI} ${WRITEABLE_SIZE} ${LINUX_RAID_TYPE} ${ROOT_SKIP} ${Device}
		DoOrExit CREATE CreatePartition ${PARTNO_PATCH} ${PATCH_SIZE} ${LINUX_FS_TYPE} ${PATCH_SKIP} ${Device}
	done

	# assmble md0
	Devices=$(GetSortedExistingInstallableDevices 1)
	num=$(Echo $Devices | /bin/wc -w)
	/sbin/mdadm -C /dev/md0 -e 0.9 -amd -R -l1 --force -n$num $Devices

	for Device in $(GetSortedExistingInstallableDevices 2); do
		DoOrExit MKFS MakeSystemFS "$Device"
	done
}

InitEMMCSysDisks ()
{
	# This should be model-specific partition, but there only has VS750HD which support EMMC Boot currently.
	local DISKNODE="/dev/mmcblk0"
	local PARTNO_ROOT="1"
	local PARTNO_SWAP="2"
	local WRITEABLE_SIZE=4194304
	local PATCH_SIZE=4194304
	local PARTNO_PATCH="2"
	local PATCH_SKIP=0
	
	# clean disk & create partition
	DoOrExit FDISK Sfdisk -M1 ${DISKNODE}
	DoOrExit CLEAN Sfdisk "--fast-delete" "-1" "${DISKNODE}"
	DoOrExit CREATE CreatePartition ${PARTNO_ROOT} ${WRITEABLE_SIZE} ${LINUX_FS_TYPE} ${ROOT_SKIP} ${DISKNODE}
	DoOrExit CREATE CreatePartition ${PARTNO_PATCH} ${PATCH_SIZE} ${LINUX_FS_TYPE} ${PATCH_SKIP} ${DISKNODE}

	DoOrExit MKFS MakeSystemFS "${DISKNODE}p${PARTNO_PATCH}"
}

InitRAIDSysDisks ()
{
	for RaidVol in 0 1; do
		Echo "raidtool destroy ${RaidVol}"
		Raidtool destroy ${RaidVol}
	done

	#For NVR-series, it supports USB local installation.
	#If this installation comes from local installation, clean all disks for "not install" status.
	#The reason to do this is if disks is derived from other DiskStation, crash volume may exist and
	#SurveillanceStation won't be installed.
	if [ "${SupportLocalInstall}" = "yes" ] && [ "${DO_CLEAN_INSTALL}" = "yes" ]; then
		for DiskIdx in $InstallableDisks ; do
			Sfdisk -M1 /dev/${DiskIdx}
			Sfdisk "--fast-delete" "-1" "/dev/${DiskIdx}"
			/bin/dd if=/dev/zero of=/dev/${DiskIdx} bs=1M count=1 > /dev/null 2>&1
		done
	fi

	if [ "$IsHDSeries" = yes ]; then
		DoOrExit CREATE Raidtool initsys-hdseries
	elif [ "$SupportHyperConverged" = yes ]; then
		DoOrExit CREATE Raidtool initsys-hci
	else
		DoOrExit CREATE Raidtool initsys
	fi
}

InitOneBaySysDisk ()
{
	DoOrExit CREATE Raidtool initsys-1hd
	sleep 1
	DoOrExit SYNODD synodd "$RootPartition" "$SwapPartition"
}

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
		if [ "$UniqueRD" = kvmx64 ] || [ "$UniqueRD" = kvmx64sofs ] || [ "$UniqueRD" = kvmx64v2 ]; then
			/bin/dd if=/dev/zero of=/dev/${DiskIdx} bs=512 count=10 seek=1000 > /dev/null 2>&1
		fi
	done

	if [ "$IsAliDSM" != yes ]; then
		DoOrExit CREATE CreatePartition ${PARTNO_ROOT} ${WRITEABLE_SIZE} ${LINUX_FS_TYPE} ${ROOT_SKIP} ${DISKNODE}
	fi
	DoOrExit CREATE CreatePartition ${PARTNO_SWAP} ${SWAP_SIZE} ${LINUX_SWAP_TYPE} ${SWAP_SKIP} ${DISKNODE}
	Echo "1/1" > /tmp/synodd.sda
}

if [ "$DO_CLEAN_ROOT" = "yes" ]; then
	if [ "no" = ${DO_MKFS_ROOT_ONLY} ]; then
		UnloadSynoRbd
		if [ "$IsUCOrXA" = yes ]; then
			InitUCXASysDisks

		elif [ "$SupportEmmcBoot"  = "yes" ]; then
			InitEMMCSysDisks

		elif [ "$SupportRAID" = "yes" ]; then
			InitRAIDSysDisks

		elif [ "$DO_CLEAN_DATA" = "yes" ]; then
			if [ "yes" = "$IsVDSM" ]; then
				InitVDSMSysDisks
			else
				InitOneBaySysDisk
			fi

		fi

		# We will write root compatible bit on DSM7.1
		# Before that, we can only reset it to default
		DoOrExit RESETROOTCOMPATIBLEBIT /usr/syno/sbin/reset_root_compatiblie_bit.sh

		if [ "static" = "$DiskSwap" ]; then
			DoOrExit MKSWAP /sbin/mkswap "$SwapPartition"
		fi
	fi

	if [ "$(GetKV "$SYNOINFO_DEF" systemfs)" = btrfs ] && [ "$(LayoutVer)" -ge 9 ]; then
		# Btrfs rootfs
		DoOrExit MKFS MakeBtrfsWithSubvolume "$RootPartition"

	else
		# Ext4 rootfs
		if [ "$IsUCOrXA" != yes ] &&
		   [ "$IsVDSM" != yes ] &&
		   [ "$IsAliDSM" != yes ] &&
		   [ "$IsHDSeries" != yes ] &&
		   [ "$SupportEmmcBoot" != yes ] &&
		   [ "$SupportHyperConverged" != yes ]; then
			DoOrExit MKFS MakeExt4WithPrjQuota "$RootPartition"

		else
			DoOrExit MKFS MakeFS "ext4" "$RootPartition"
		fi
	fi
fi

Mount "$RootPartition" /mnt
/bin/touch /mnt/.noroot
Umount /mnt

if [ -x /usr/syno/bin/mantool ]; then
	/usr/syno/bin/mantool -auto_poweron_disable
fi

exit 0
