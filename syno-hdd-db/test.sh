#!/usr/bin/env bash

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
#            hdlist+="${hdmodel},${fwrev}"
#        fi        
    fi
}

getm2info(){
    # ${1} is /sys/block/nvme0n1 etc
    nvmemodel=$(cat "${1}/device/model")
    nvmemodel=$(printf "%s" "$nvmemodel" | xargs)  # trim leading and trailing white space
    if [[ $2 == "nvme" ]]; then
        nvmefw=$(cat "${1}/device/firmware_rev")
    elif [[ $2 == "nvc" ]]; then
        nvmefw=$(cat "${1}/device/rev")
    fi
    nvmefw=$(printf "%s" "$nvmefw" | xargs)  # trim leading and trailing white space

#    if [[ -n "$nvmemodel" ]] && [[ -n "$nvmefw" ]]; then
#        nvmelist+="${nvmemodel},${nvmefw}"
#    fi
}

getcardmodel(){
    # Get M.2 card model (if M.2 drives found)
    # ${1} is /dev/nvme0n1 etc
    if [[ ${#nvmelist[@]} -gt "0" ]]; then
        cardmodel=$(tmpRoot/usr/syno/bin/synodisk --m2-card-model-get "${1}")
        if [[ $cardmodel =~ M2D[0-9][0-9] ]]; then
            # M2 adaptor card
            if [[ -f "${model}_${cardmodel,,}${version}.db" ]]; then
                m2carddblist+=("${model}_${cardmodel,,}${version}.db")  # M.2 card's db file
            fi
            if [[ -f "${model}_${cardmodel,,}.db" ]]; then
                m2carddblist+=("${model}_${cardmodel,,}.db")            # M.2 card's db file
            fi
            m2cardlist+=("$cardmodel")                                  # M.2 card
        elif [[ $cardmodel =~ E[0-9][0-9]+M.+ ]]; then
            # Ethernet + M2 adaptor card
            if [[ -f "${model}_${cardmodel,,}${version}.db" ]]; then
                m2carddblist+=("${model}_${cardmodel,,}${version}.db")  # M.2 card's db file
            fi
            if [[ -f "${model}_${cardmodel,,}.db" ]]; then
                m2carddblist+=("${model}_${cardmodel,,}.db")            # M.2 card's db file
            fi
            m2cardlist+="$cardmodel"                                  # M.2 card
        fi
    fi
}

m2_pool_support(){
    if [[ -f /tmpRoot/run/synostorage/disks/"$(basename -- "${1}")"/m2_pool_support ]]; then  # GitHub issue #86, 87
        echo 1 > /tmpRoot/run/synostorage/disks/"$(basename -- "${1}")"/m2_pool_support
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
        sata*|sas*)
            if [[ $d =~ (sas|sata)[0-9][0-9]?[0-9]?$ ]]; then
                # Get drive model and firmware version
                getdriveinfo "$d"
            fi
        ;;
        nvme*)
            if [[ $d =~ nvme[0-9][0-9]?n[0-9][0-9]?$ ]]; then
                if [[ $m2 != "no" ]]; then
                    getm2info "$d" "nvme"
                    # Get M.2 card model if in M.2 card
                    getcardmodel "/dev/$(basename -- "${d}")"

                    # Enable creating M.2 storage pool and volume in Storage Manager
                    m2_pool_support "$d"

                    rebootmsg=yes  # Show reboot message at end
                fi
            fi
        ;;
        nvc*)  # M.2 SATA drives (in PCIe card only?)
            if [[ $d =~ nvc[0-9][0-9]?$ ]]; then
                if [[ $m2 != "no" ]]; then
                    getm2info "$d" "nvc"
                    # Get M.2 card model if in M.2 card
                    getcardmodel "/dev/$(basename -- "${d}")"

                    # Enable creating M.2 storage pool and volume in Storage Manager
                    m2_pool_support "$d"

                    rebootmsg=yes  # Show reboot message at end
                fi
            fi
        ;;
    esac
done
