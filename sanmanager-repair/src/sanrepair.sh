#!/bin/bash

# Make things safer
set -euo pipefail

while true; do
    sleep 5
    status=$(synopkg status ScsiTarget)
    if [ -n "$(echo "$status" | grep error)" ]; then
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
    status=$(synopkg status ScsiTarget)
    if [ -z "$(echo "$status" | grep error)" ]; then
        break
    fi
done
