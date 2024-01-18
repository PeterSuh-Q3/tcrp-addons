#!/bin/bash

# Make things safer
set -euo pipefail

if [ $(synopkg status ScsiTarget | grep failed | wc -l) -gt 0 ]; then

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
