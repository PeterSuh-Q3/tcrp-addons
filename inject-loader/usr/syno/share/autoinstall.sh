#!/bin/sh
# Copyright (c) 2020-2020 Synology Inc. All rights reserved.

. /usr/syno/share/environments.sh

AutoInstall() { # Mnt
        if [ $# -ne 1 ]; then
                Echo "AutoInstall: Wrong usage"
                return 255
        fi

        local Mnt="$1"; shift

        if [ "$SupportAutoInstall" != "yes" ]; then
                Echo "AutoInstall: Not supported; skipped"
                return 255
        fi

        Echo "AutoInstall: Start"

        /usr/syno/share/autoinstall/cleanup_rootdevice.sh "$Mnt"
        /usr/syno/share/autoinstall/prepare_files.sh "$Mnt"

        # Autoinstall models do not backup flash image, so we have no choice but to copy
        # /etc.defaults/VERSION to $Mnt/.syno/patch/VERSION, assuming that backup hda1 agrees with
        # the current junior
        Mkdir -p "$Mnt"/.syno/patch
        Cp /etc.defaults/VERSION "$Mnt"/.syno/patch/VERSION

        /bin/touch /tmp/upgrade_files_prepared_from_autoinstall

        Echo "AutoInstall: Finished"
}

AutoInstall "$@"
