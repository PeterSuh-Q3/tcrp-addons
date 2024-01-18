#!/bin/bash

# Make things safer
set -euo pipefail

while true; do
    if dmesg | grep -q "fuse init"; then
        break
    fi
    sleep 1
done

if [ -n "$(synopkg status ScsiTarget | grep error)" ]; then
    modprobe target_core_mod
    modprobe target_core_iblock
    modprobe target_core_file
    modprobe target_core_multi_file
    modprobe target_core_user
    modprobe iscsi_target_mod
    modprobe tcm_loop
    modprobe vhost
    modprobe vhost_scsi

    synopkg start ScsiTarget
fi
