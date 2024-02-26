#!/bin/sh
# Copyright (c) 2020-2020 Synology Inc. All rights reserved.

AddPrefix() {
	local prefix="${1}"; shift

	xargs -I{} echo "${prefix}{}"
}
FilterExisting() {
	xargs -I{} /bin/ls -d "{}"
}
FilterInOfSynoPartition() {
	IFS= read -r line
	for device in ${line}; do
		local port=
		port="$(/usr/syno/bin/synodiskport -portcheck "${device}")"
		if [ "SYS" != "${port}" ] && /usr/syno/bin/synocheckpartition "${device}"; then
			# If a device is of porttype SYS, it is a SATADOM and expected not of synopartition;
			# otherwise, it should be of synopartion and thus we filter out those not. Note that
			# SSDCache only has partition 1 and thus not of synopartition.
			continue
		fi
		echo "${device}"
	done
}
GetInstallableDevices() {
	local partno="${1}"; shift

	for disk in $(/usr/syno/bin/synodiskport -installable_disk_list | FilterInOfSynoPartition); do
		/usr/syno/bin/synodiskport -part_name_get "${partno}" "${disk}"
	done
}
GetSortedExistingInstallableDevices() {
	local partno="${1}"; shift

	GetInstallableDevices "${partno}" \
		| AddPrefix "/dev/" \
		| FilterExisting
}
