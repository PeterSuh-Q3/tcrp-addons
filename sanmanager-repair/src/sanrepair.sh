#!/bin/bash

# Make things safer
set -euo pipefail

sleep 90
if [ $(synopkg status ScsiTarget | grep error | wc -l) -gt 0 ]; then
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

sleep 30
if [ $(synopkg status ScsiTarget | grep error | wc -l) -gt 0 ]; then
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

# Loop through each volume directory
for volume_dir in /volume*; do
    # Check if the directory exists and is a directory
    if [ -d "$volume_dir" ]; then
        # Form the path to iscsi_lun.conf file
        iscsi_lun_conf="$volume_dir/@iSCSI/LUN/iscsi_lun.conf"
        
        # Check if iscsi_lun.conf file exists
        if [ -f "$iscsi_lun_conf" ]; then
            echo "Contents of $iscsi_lun_conf:"
            # Extract uuid values from iscsi_lun.conf and store in vuuid variable
            vuuid=$(grep -oP 'uuid=\K\S+' "$iscsi_lun_conf")
            
            # Check if vuuid is not empty
            if [ -n "$vuuid" ]; then
                # Loop through each element in vuuid
                for uuid in $vuuid; do
                    # Print each uuid element
                    echo "$uuid"
                    mkdir -p  /config/target/iscsi/iqn.${uuid}
                    mkdir -p  /config/target/loopback/naa.${uuid}
                    mkdir -p  /config/target/iscsi/iqn.${uuid}/tpgt_1/attrib
                    chmod 777 /config/target/iscsi/iqn.${uuid}/tpgt_1/attrib
                    mkdir -p  /config/target/loopback/naa.${uuid}/tpgt_1
                    chmod 777 /config/target/loopback/naa.${uuid}/tpgt_1
                done
            fi
        else
            echo "iscsi_lun.conf not found in $volume_dir"
        fi
    fi
done
   
