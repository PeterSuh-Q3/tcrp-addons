#!/bin/sh
# Copyright (c) 2020-2020 Synology Inc. All rights reserved.

. /usr/syno/share/environments.sh
. /usr/syno/share/util.sh
. /usr/syno/share/get_installable_devices.sh
. /usr/syno/share/mkfs.sh

WithAnyMounted() { # <stdin: devices...> mnt cmd...
        local mnt="$1"; shift

        while IFS= read -r device; do
                if Mount "$device" "$mnt"; then
                        "$@"

                        local ret=$?
                        Umount -f "$mnt"
                        return $ret
                else
                        Echo "Failed to mount $device on $mnt"
                        Umount -f "$mnt"
                fi
        done

        return 255
}

WithAnyInstallableDeviceMounted() { # partno mnt cmd...
        local partno="$1"; shift
        local mnt="$1"; shift

        GetSortedExistingInstallableDevices "$partno" | WithAnyMounted "$mnt" "$@"
}

PrepareFiles() { # Mnt
        if [ $# -ne 1 ]; then
                Echo "PrepareFiles: Wrong usage"
                return 255
        fi

        local Mnt="$1"; shift

        Echo "PrepareFiles: Start"

        local ret=0
        local PatchMnt=/tmp/autoinstall_patch_mnt

        if [ "$IsUCOrXA" = "yes" ] || [ "$SupportEmmcBoot" = "yes" ]; then
                WithDirectory "$PatchMnt" WithAnyInstallableDeviceMounted 2 "$PatchMnt" \
                        /usr/syno/share/autoinstall/prepare_files_from_patch_mnt.sh "$PatchMnt" "$Mnt"
                ret=$?

        elif [ "$UniqueRD" = "nextkvmx64" ]; then
                echo 1 >/proc/sys/kernel/syno_install_flag

                WithDirectory "$PatchMnt" WithMounted "/dev/synoboot4" "$PatchMnt" \
                        /usr/syno/share/autoinstall/prepare_files_from_extracted.sh "$PatchMnt" "$Mnt"
                ret=$?

                echo 0 >/proc/sys/kernel/syno_install_flag
        fi

        Echo "PrepareFiles: Finished [$ret]"
        return $ret
}

PrepareFiles "$@"
