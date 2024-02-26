#!/bin/sh

# shellcheck disable=SC2034 # Providing variables for other scripts which source this script.

. /usr/syno/share/environments.sh

if [ "$SupportRAID" = yes ]; then
	DataPartition=""

elif [ "$IsAliDSM" = yes ]; then
	DataPartition=/dev/sda7

elif [ "$SupportEmmcBoot" = yes ]; then
	DataPartition=/dev/mmcblk0p3

elif [ "$SupportPortMappingV2" = yes ]; then
	DataPartition=/dev/sata1p3

else
	DataPartition=/dev/sda3
fi
