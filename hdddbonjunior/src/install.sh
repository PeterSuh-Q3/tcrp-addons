#!/usr/bin/env bash

model=$(uname -u | cut -d '_' -f3)
echo model "${model}" >&2  # debug

# Host db files
dbpath="/var/lib/disk-compatibility/"
dbfile=$(ls "${dbpath}"*"${model}_host_v7.db")
echo dbfile "${dbfile}" >&2  # debug

if [ "${1}" = "modules" ]; then

  #------------------------------------------------------------------------------
  # Get list of installed SATA, SAS and M.2 NVMe/SATA drives,
  # PCIe M.2 cards and connected Expansion Units.

  fixdrivemodel(){
    # Remove " 00Y" from end of Samsung/Lenovo SSDs  # Github issue #13
    if echo "${1}" | grep -q "MZ.* 00Y"; then
        hdmodel=$(echo "${1}" | sed 's/ 00Y.*//')
    fi

    # Brands that return "BRAND <model>" and need "BRAND " removed.
    if echo "${1}" | grep -q "^[A-Za-z]\{1,7\} "; then
        #see  Smartmontools database in /var/lib/smartmontools/drivedb.db
        hdmodel=${hdmodel#"WDC "}       # Remove "WDC " from start of model name
        hdmodel=${hdmodel#"HGST "}      # Remove "HGST " from start of model name
        hdmodel=${hdmodel#"TOSHIBA "}   # Remove "TOSHIBA " from start of model name

        # Old drive brands
        hdmodel=${hdmodel#"Hitachi "}   # Remove "Hitachi " from start of model name
        hdmodel=${hdmodel#"SAMSUNG "}   # Remove "SAMSUNG " from start of model name
        hdmodel=${hdmodel#"FUJISTU "}   # Remove "FUJISTU " from start of model name
        hdmodel=${hdmodel#"APPLE HDD "} # Remove "APPLE HDD " from start of model name
    fi
  }

  get_size_gb(){ 
      # $1 is /sys/block/sata1 or /sys/block/nvme0n1 etc
      local disk_size_gb
      #disk_size_gb=$(synodisk --info /dev/"$(basename -- "$1")" 2>/dev/null | grep 'Total capacity' | awk '{print int($4 * 1.073741824)}')
      disk_size_gb=$(fdisk -l "$1" 2>/dev/null | grep GB | cut -d' ' -f3)
      echo "$disk_size_gb"
  }

  getdriveinfo(){
    # ${1} is /sys/block/sata1 etc

    REVISION="$(uname -a | cut -d ' ' -f4)"
    echo "REVISION = ${REVISION}"

    # Skip USB drives
    usb=$(grep "$(basename -- "${1}")" /proc/mounts | grep "[Uu][Ss][Bb]" | cut -d" " -f1-2)
    if [[ ! $usb ]]; then
    
        # Get drive model
        hdmodel=$(cat "${1}/device/model")
        hdmodel=$(printf "%s" "${hdmodel}" | xargs)  # trim leading and trailing white space

        # Fix dodgy model numbers
        if [ $(echo  "${hdmodel}" | grep Virtual | wc -l) -eq 0 ]; then
            fixdrivemodel "${hdmodel}"
        fi

        # Get drive firmware version
        #fwrev=$(cat "${1}/device/rev")
        #fwrev=$(printf "%s" "${fwrev}" | xargs)  # trim leading and trailing white space

        device="/dev/$(basename -- "${1}")"
        # Account for SSD drives with spaces in their model name/number
        chmod +x ./hdparm701
        chmod +x ./hdparm711
        chmod +x ./hdparm720

        if [[ $2 == "sd" ]]; then
          if [ -f ${1}/device/sas_address ]; then
            fwrev="1.13.2"
          else
            if [ ${REVISION} = "#42218" ]; then
                fwrev=$(./hdparm701 -I "${device}" | grep Firmware | cut -d':' -f2- | cut -d ' ' -f 3 )
            elif [ ${REVISION} = "#42962" ]; then
                fwrev=$(./hdparm711 -I "${device}" | grep Firmware | cut -d':' -f2- | cut -d ' ' -f 3 )
            else
                fwrev=$(./hdparm720 -I "${device}" | grep Firmware | cut -d':' -f2- | cut -d ' ' -f 3 )
            fi
          fi  
        elif [[ $2 == "nvme" ]]; then
            fwrev=$(cat "$1/device/firmware_rev")
        fi

        echo hdmodel "${hdmodel}" >&2  # debug
        echo fwrev "${fwrev}" >&2      # debug

        if [ -n "${hdmodel}" ] && [ -n "${fwrev}" ]; then
          if [ $(cat "${dbfile}" | grep "${hdmodel}" | wc -l) -gt 0 ]; then
            echo "${hdmodel} is already exists in ${dbfile}, skip writing to /etc/disk_db.json" >&2  # debug
          else
              if grep '"'"${hdmodel}"'":' /etc/disk_db.json >/dev/null; then
                 # Replace  "WD40PURX-64GVNY0":{  with  "WD40PURX-64GVNY0":{"80.00A80":{ ... }}},
                  echo "Insert firmware version:"  # debug
                  sed -i 's#"'"${hdmodel}"'":{#"'"${hdmodel}"'":{"'"${fwrev}"'":{"size_gb":"'"${size_gb}"'","compatibility_interval":[{"compatibility":"support","not_yet_rolling_status":"support","fw_dsm_update_status_notify":false,"barebone_installable":true,"barebone_installable_v2":"auto","smart_test_ignore":false,"smart_attr_ignore":false}]},#' /etc/disk_db.json
              else
                 # Add  "WD40PURX-64GVNY0":{"80.00A80":{ ... }}},"default":{ ... }}}
                  echo "Append drive and firmware:"  # debug
                  jsondata='"'"${hdmodel}"'":{"'"${fwrev}"'":{"size_gb":"'"${size_gb}"'","compatibility_interval":[{"compatibility":"support","not_yet_rolling_status":"support","fw_dsm_update_status_notify":false,"barebone_installable":true,"barebone_installable_v2":"auto","smart_test_ignore":false,"smart_attr_ignore":false}]},
                  "default":{"compatibility_interval":[{"size_gb":"'"${size_gb}"'","compatibility":"support","not_yet_rolling_status":"support","fw_dsm_update_status_notify":false,"barebone_installable":true,"barebone_installable_v2":"auto","smart_test_ignore":false,"smart_attr_ignore":false}]}}' && echo $jsondata >> /etc/disk_db.json
                  echo "," >> /etc/disk_db.json
              fi                    
          fi
       fi   
    fi
  }

  echo "{" > /etc/disk_db.json
  for d in /sys/block/*; do
    # $d is /sys/block/sata1 etc
    case "$(basename -- "${d}")" in
      sd*|hd*|sata*|sas*)
        size_gb=$(get_size_gb "${d}")
        getdriveinfo "$d" "sd"
      ;;
      nvme*)
        size_gb=$(get_size_gb "${d}")
        getdriveinfo "$d" "nvme"
      ;;
    esac
  done
  sed -i '$s/,$/}/' /etc/disk_db.json
  #cat /etc/disk_db.json

  diskdata=$(jq . /etc/disk_db.json)
  jsonfile=$(jq '.disk_compatbility_info |= .+ '"$diskdata" ${dbfile}) && echo $jsonfile | jq . > ${dbfile}
  # print last 8 elements
  #jq '.disk_compatbility_info | to_entries | map(select(.value != null)) | .[-8:]' ${dbfile}

  cp -vf ${dbfile} /etc/

  #synosetkeyvalue "/etc.defaults/synoinfo.conf" "drive_db_test_url" "127.0.0.1"
  #synosetkeyvalue "/etc/synoinfo.conf" "drive_db_test_url" "127.0.0.1"
  
elif [ "${1}" = "late" ]; then
  echo "copy disk_db.json file....."
  cp -vf /etc/disk_db.json /tmpRoot/etc/disk_db.json

  echo "copy db file to /tmpRoot/....."
  cp -vf /etc/*${model}_host_v7.db /tmpRoot/etc/
  cp -vf /etc/*${model}_host_v7.db /tmpRoot/var/lib/disk-compatibility/

  echo 'drive_db_test_url="127.0.0.1"' >> /tmpRoot/etc.defaults/synoinfo.conf
  echo 'drive_db_test_url="127.0.0.1"' >> /tmpRoot/etc/synoinfo.conf

fi
