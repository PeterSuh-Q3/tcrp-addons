#!/bin/sh

dbpath=tmpRoot/var/lib/disk-compatibility/
synoinfo="/tmpRoot/etc.defaults/synoinfo.conf"
adapter_cards="/tmpRoot/etc.defaults/adapter_cards.conf"
modeldtb="/tmpRoot/etc.defaults/model.dtb"

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
        fwrev=$(/tmpRoot/usr/syno/bin/syno_hdd_util --ssd_detect | grep "$device " | awk '{print $(NF-3)}')  # GitHub issue #86, 87
        echo $hdmodel
        echo $fwrev
#        if [[ -n "$hdmodel" ]] && [[ -n "$fwrev" ]]; then
#            hdlist+=("$hdmodel,$fwrev");
#        fi        
    fi
}

for d in /sys/block/*; do
    # $d is /sys/block/sata1 etc
    case "$(basename -- "${d}")" in
        sd*|hd*)
            if [[ $d =~ [hs]d[a-z][a-z]?$ ]]; then
                # Get drive model and firmware version
                echo $d 
                getdriveinfo "$d"
            fi
        ;;
    esac
done
