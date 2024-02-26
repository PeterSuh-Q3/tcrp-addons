#!/bin/sh

# shellcheck disable=SC2034 # Providing variables for other scripts which source this script.

. /usr/syno/share/environments.sh

if [ "$SupportRAID" = yes ]; then
	RootPartition=/dev/md0
	SwapPartition=/dev/md1

	if [ -L /dev/system-root ]; then
		RootPartition=/dev/system-root
	fi

elif [ "$IsAliDSM" = yes ]; then
	RootPartition=/dev/sda5
	SwapPartition=/dev/sda6

elif [ "$SupportEmmcBoot" = yes ]; then
	RootPartition=/dev/mmcblk0p1
	SwapPartition=/dev/mmcblk0p2

elif [ "$SupportPortMappingV2" = yes ]; then
	RootPartition=/dev/sata1p1
	SwapPartition=/dev/sata1p2

else
	RootPartition=/dev/sda1
	SwapPartition=/dev/sda2
fi
