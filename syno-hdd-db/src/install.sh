#!/usr/bin/env bash

if [ "${1}" = "modules" ]; then

  #------------------------------------------------------------------------------
  # Get list of installed SATA, SAS and M.2 NVMe/SATA drives,
  # PCIe M.2 cards and connected Expansion Units.

  fixdrivemodel(){
    # Remove " 00Y" from end of Samsung/Lenovo SSDs  # Github issue #13
    if [[ ${1} =~ MZ.*" 00Y" ]]; then
        hdmodel=$(printf "%s" "${1}" | sed 's/ 00Y.*//')
    fi

    # Brands that return "BRAND <model>" and need "BRAND " removed.
    if [[ ${1} =~ ^[A-Za-z]{1,7}" ".* ]]; then
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

  getdriveinfo(){
    # ${1} is /sys/block/sata1 etc

    REVISION="$(uname -a | cut -d ' ' -f4)"
    echo "REVISION = ${REVISION}"

    # Skip USB drives
    usb=$(grep "$(basename -- "${1}")" /proc/mounts | grep "[Uu][Ss][Bb]" | cut -d" " -f1-2)
    if [[ ! $usb ]]; then
    
        # Get drive model
        hdmodel=$(cat "${1}/device/model")
        hdmodel=$(printf "%s" "$hdmodel" | xargs)  # trim leading and trailing white space

        # Fix dodgy model numbers
        if [ $(echo  "$hdmodel" | grep Virtual | wc -l) -eq 0 ]; then
            fixdrivemodel "$hdmodel"
        fi

        # Get drive firmware version
        #fwrev=$(cat "${1}/device/rev")
        #fwrev=$(printf "%s" "$fwrev" | xargs)  # trim leading and trailing white space

        device="/dev/$(basename -- "${1}")"
        # Account for SSD drives with spaces in their model name/number
        chmod +x ./hdparm711
        chmod +x ./hdparm720
        
        if [ ${REVISION} = "#42962" ]; then
            fwrev=$(./hdparm711 -I "$device" | grep Firmware | cut -d':' -f2- | cut -d ' ' -f 3 )
        else
            fwrev=$(./hdparm720 -I "$device" | grep Firmware | cut -d':' -f2- | cut -d ' ' -f 3 )
        fi

        echo hdmodel "$hdmodel" >&2  # debug
        echo fwrev "$fwrev" >&2      # debug
        
        if [ -n "$hdmodel" ] && [ -n "$fwrev" ]; then
            echo "Append drive and firmware:" >&2 # debug
            jsondata='"${hdmodel}":{"${fwrev}":{"compatibility_interval":[{"compatibility":"support","not_yet_rolling_status":"support","fw_dsm_update_status_notify":false,"barebone_installable":true}]},
            "default":{"compatibility_interval":[{"compatibility":"support","not_yet_rolling_status":"support","fw_dsm_update_status_notify":false,"barebone_installable":true}]}}' && echo $jsondata >> /etc/disk_db.json
            echo "," >> /etc/disk_db.json
        fi
    fi
  }

  echo "{" > /etc/disk_db.json
  for d in /sys/block/*; do
    # $d is /sys/block/sata1 etc
    case "$(basename -- "${d}")" in
      sd*|hd*|sata*|sas*)
        getdriveinfo "$d"
      ;;
    esac
  done
  sed -i '$s/,$/}/' /etc/disk_db.json
  
elif [ "${1}" = "late" ]; then

  model=$(uname -u | cut -d '_' -f3)
  echo model "$model" >&2  # debug
  
  # Host db files
  dbpath="/tmpRoot/var/lib/disk-compatibility/"
  dbfile=$(ls "${dbpath}"*"${model}_host_v7.db")
  echo dbfile "$dbfile" >&2  # debug

  diskdata=$(/tmpRoot/bin/jq . /etc/disk_db.json)
  jsonfile=$(/tmpRoot/bin/jq '.disk_compatbility_info |= .+ '"$diskdata" $dbfile) && echo $jsonfile | jq . > $dbfile
  
fi

exit
