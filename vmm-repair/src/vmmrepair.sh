#!/bin/bash

LOG_FILE="/var/log/synoscgi.log"
uuid=""

tail -n0 -F "$LOG_FILE" | while read line; do
    if [[ $line == *"vpd_unit_sn:"* ]]; then
        # Extracting vpd_unit_sn value
        uuid=$(echo "$line" | grep -oP 'vpd_unit_sn:\s*\K\S+')
        echo "Found vpd_unit_sn: $uuid"
        # Do something with the uuid value here
        
        mkdir -p  /config/target/iscsi/iqn.${uuid}
        mkdir -p  /config/target/loopback/naa.${uuid}
        mkdir -p  /config/target/iscsi/iqn.${uuid}/tpgt_1/attrib
        chmod 777 /config/target/iscsi/iqn.${uuid}/tpgt_1/attrib
        mkdir -p  /config/target/loopback/naa.${uuid}/tpgt_1
        chmod 777 /config/target/loopback/naa.${uuid}/tpgt_1
    fi
done
