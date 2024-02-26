#!/bin/sh

. /usr/syno/share/environments.sh
. /usr/syno/share/kernelversion.sh

get_mkfs_option()
{
	case "$1" in
		ext4)
			echo "-F -P -O ^metadata_csum"
			;;
		btrfs)
			echo "-f -L$(date '+%Y.%m.%d-%H:%M:%S')_v$(GetKV /etc.defaults/VERSION buildnumber)"
			;;
	esac
}

GetPrjQuotaOpt()
{
	case "$1" in
		ext4)
			:
			;;
		*)
			return 0
			;;
	esac
	if [ "$(KernelVersionCode "$(KernelVersion)")" -ge "$(KernelVersionCode "4.4")" ] && \
		[ "42446" -le "$(/bin/get_key_value /etc.defaults/VERSION buildnumber)" ]; then
		echo "-Oproject,quota"
	else
		echo ""
	fi
}

MakeFS() { # fs options... device
	local fs="$1"; shift

	# shellcheck disable=SC2046 # we abuse word splitting to inject multiple options for mkfs
	"/sbin/mkfs.${fs}" $(get_mkfs_option "$fs") "$@"
}

MakeExt4WithPrjQuota()
{
	# shellcheck disable=SC2046
	MakeFS "ext4" $(GetPrjQuotaOpt "ext4") "$@"
}

MakeBtrfsWithSubvolume()
{
	local dev subvolid sysmnt="/tmpBtrfs" Btrfs="/sbin/btrfs"

	[ -x "$Btrfs" ] || return 1

	MakeFS "btrfs" "$@"
	if [ "$?" -eq 0 ]; then
		for dev in "$@"; do :; done

		Mkdir "$sysmnt"
		Mount "$dev" "$sysmnt"
		$Btrfs quota enable-v2 "$sysmnt"
		$Btrfs usrquota enable-v2 "$sysmnt"
		$Btrfs subvolume create "$sysmnt/@"
		$Btrfs subvolume create "$sysmnt/@syno"
		/bin/chmod 0755 "$sysmnt/@" "$sysmnt/@syno"
		subvolid=$(btrfs subvolume show "$sysmnt/@" | Grep "Subvolume ID" | xargs | Cut -d' ' -f3)
		$Btrfs subvolume set-default "$subvolid" "$sysmnt"
		Umount "$sysmnt"
	fi
}

MakeSystemFS() { # options... device
	MakeFS "$(/bin/get_key_value /etc.defaults/synoinfo.conf systemfs)" "$@"
}

MakeDefaultFS() { # options... device
	MakeFS "$(/bin/get_key_value /etc.defaults/synoinfo.conf defaultfs)" "$@"
}
