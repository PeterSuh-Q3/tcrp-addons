#!/usr/bin/env bash

# Shell Colors
#Black='\e[0;30m'
Red='\e[0;31m'
#Green='\e[0;32m'
Yellow='\e[0;33m'
#Blue='\e[0;34m'
#Purple='\e[0;35m'
Cyan='\e[0;36m'
#White='\e[0;37m'
Error='\e[41m'
Off='\e[0m'

model=$(uname -u | cut -d '_' -f3)
# Host db files
dbfile="/tmpRoot/var/lib/disk-compatibility/${model}_host_v7.db"

echo model "$model" >&2  # debug
echo dbfile "$dbfile" >&2  # debug
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
        #see  Smartmontools database in /tmpRoot/var/lib/smartmontools/drivedb.db
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

    # Skip USB drives
    usb=$(grep "$(basename -- "${1}")" /tmpRoot/proc/mounts | grep "[Uu][Ss][Bb]" | cut -d" " -f1-2)
    if [[ ! $usb ]]; then
    
        # Get drive model
        hdmodel=$(cat "${1}/device/model")
        hdmodel=$(printf "%s" "$hdmodel" | xargs)  # trim leading and trailing white space

        # Fix dodgy model numbers
        fixdrivemodel "$hdmodel"

        # Get drive firmware version
        #fwrev=$(cat "${1}/device/rev")
        #fwrev=$(printf "%s" "$fwrev" | xargs)  # trim leading and trailing white space

        device="/dev/$(basename -- "${1}")"
        #fwrev=$(syno_hdd_util --ssd_detect | grep "$device " | awk '{print $2}')      # GitHub issue #86, 87
        # Account for SSD drives with spaces in their model name/number
        fwrev=$(/tmpRoot/bin/hdparm -I "$device" | grep Firmware | awk '{print $3}')  # GitHub issue #86, 87
        echo $hdmodel
        echo $fwrev
        if [[ $hdmodel ]] && [[ $fwrev ]]; then
            updatedb $dbfile
        fi
    fi
}

if [ "${1}" = "late" ]; then

for d in /sys/block/*; do
    # $d is /sys/block/sata1 etc
    case "$(basename -- "${d}")" in
        sd*|hd*)
            if [[ $d =~ [hs]d[a-z][a-z]?$ ]]; then
                # Get drive model and firmware version
                getdriveinfo "$d"
            fi
        ;;
        sata*|sas*)
            if [[ $d =~ (sas|sata)[0-9][0-9]?[0-9]?$ ]]; then
                # Get drive model and firmware version
                getdriveinfo "$d"
            fi
        ;;
    esac
done


#------------------------------------------------------------------------------
# Check databases and add our drives if needed
editcount(){
    # Count drives added to host db files
    if [[ ${1} =~ .*\.db$ ]]; then
        db1Edits=$((db1Edits +1))
    elif [[ ${1} =~ .*\.db.new ]]; then
        db2Edits=$((db2Edits +1))
    fi
}

editdb7(){
    if [[ ${1} == "append" ]]; then  # model not in db file
        #if sed -i "s/}}}/}},\"$hdmodel\":{$fwstrng$default/" "$2"; then  # append
        if sed -i "s/}}}/}},\"${hdmodel//\//\\/}\":{$fwstrng$default/" "$2"; then  # append
            echo -e "Added ${Yellow}$hdmodel${Off} to ${Cyan}$(basename -- "$2")${Off}"
            editcount "$2"
        else
            echo -e "\n${Error}ERROR 6a${Off} Failed to update $(basename -- "$2")${Off}"
            #exit 6
        fi

    elif [[ ${1} == "insert" ]]; then  # model and default exists
        #if sed -i "s/\"$hdmodel\":{/\"$hdmodel\":{$fwstrng/" "$2"; then  # insert firmware
        if sed -i "s/\"${hdmodel//\//\\/}\":{/\"${hdmodel//\//\\/}\":{$fwstrng/" "$2"; then  # insert firmware
            echo -e "Updated ${Yellow}$hdmodel${Off} to ${Cyan}$(basename -- "$2")${Off}"
            #editcount "$2"
        else
            echo -e "\n${Error}ERROR 6b${Off} Failed to update $(basename -- "$2")${Off}"
            #exit 6
        fi

    elif [[ ${1} == "empty" ]]; then  # db file only contains {}
        #if sed -i "s/{}/{\"$hdmodel\":{$fwstrng${default}}/" "$2"; then  # empty
        if sed -i "s/{}/{\"${hdmodel//\//\\/}\":{$fwstrng${default}}/" "$2"; then  # empty
            echo -e "Added ${Yellow}$hdmodel${Off} to ${Cyan}$(basename -- "$2")${Off}"
            editcount "$2"
        else
            echo -e "\n${Error}ERROR 6c${Off} Failed to update $(basename -- "$2")${Off}"
            #exit 6
        fi

    fi
}


updatedb(){
    echo hdmodel "$hdmodel" >&2  # debug
    echo fwrev "$fwrev" >&2      # debug

    if grep "$hdmodel"'":{"'"$fwrev" "$1" >/dev/null; then
        echo -e "${Yellow}$hdmodel${Off} already exists in ${Cyan}$(basename -- "$1")${Off}" >&2
    else
        fwstrng=\"$fwrev\"
        fwstrng="$fwstrng":{\"compatibility_interval\":[{\"compatibility\":\"support\",\"not_yet_rolling_status\"
        fwstrng="$fwstrng":\"support\",\"fw_dsm_update_status_notify\":false,\"barebone_installable\":true}]},

        default=\"default\"
        default="$default":{\"compatibility_interval\":[{\"compatibility\":\"support\",\"not_yet_rolling_status\"
        default="$default":\"support\",\"fw_dsm_update_status_notify\":false,\"barebone_installable\":true}]}}}

        if grep '"disk_compatbility_info":{}' "$1" >/dev/null; then
           # Replace  "disk_compatbility_info":{}  with  "disk_compatbility_info":{"WD40PURX-64GVNY0":{"80.00A80":{ ... }}},"default":{ ... }}}}
            #echo "Edit empty db file:"  # debug
            editdb7 "empty" "$1"

        elif grep '"'"$hdmodel"'":' "$1" >/dev/null; then
           # Replace  "WD40PURX-64GVNY0":{  with  "WD40PURX-64GVNY0":{"80.00A80":{ ... }}},
            #echo "Insert firmware version:"  # debug
            editdb7 "insert" "$1"

        else
           # Add  "WD40PURX-64GVNY0":{"80.00A80":{ ... }}},"default":{ ... }}}
            #echo "Append drive and firmware:"  # debug
            editdb7 "append" "$1"
        fi
    fi
}

fi

exit
