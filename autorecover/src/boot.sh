#!/bin/bash
#
# Author : PeterSuh-Q3
# Date : 250702
# User Variables :
###############################################################################

BOOTVER="0.1.3m"
FRIENDLOG="/mnt/tcrp/friendlog.log"
AUTOUPDATES="1"
userconfigfile=/mnt/tcrp/user_config.json

function version() {
    shift 1
    echo $BOOTVER
    [ "$1" == "history" ] && history
}

function getredpillko() {

    if [ ! -n "$IP" ]; then
        msgalert "The getredpillko() cannot proceed because there is no IP yet !!!! \n"
        exit 99
    fi

    cd /root

    echo "Removing any old redpill.ko modules"
    [ -f /root/redpill.ko ] && rm -f /root/redpill.ko

    DSM_VERSION=$(cat /mnt/tcrp-p1/GRUB_VER | grep DSM_VERSION | cut -d "=" -f2 | sed 's/"//g')

    if [ "${ORIGIN_PLATFORM}" = "epyc7002" ]; then    
        KVER="5.10.55"
    elif [ "${ORIGIN_PLATFORM}" = "v1000nk" ]; then
        KVER="5.10.55"
    elif [ "${ORIGIN_PLATFORM}" = "bromolow" ]; then
        KVER="3.10.108"    
    elif [ "${ORIGIN_PLATFORM}" = "avoton" ]; then
        KVER="3.10.108"
    elif [ "${ORIGIN_PLATFORM}" = "braswell" ]; then
        KVER="3.10.108"
    elif [ "${ORIGIN_PLATFORM}" = "cedarview" ]; then
        KVER="3.10.108"
    else
        if [ ${DSM_VERSION} -lt 64570 ]; then
            KVER="4.4.180"
        else
            KVER="4.4.302"
        fi
    fi
    
    echo "KERNEL VERSION of getredpillko() is ${KVER}"
    echo "Downloading ${ORIGIN_PLATFORM} ${KVER}+ redpill.ko ..."

    LATESTURL="`curl --connect-timeout 5 -skL -w %{url_effective} -o /dev/null "${PROXY}https://github.com/PeterSuh-Q3/redpill-lkm${v}/releases/latest"`"

    if [ $? -ne 0 ]; then
        msgalert "Error downloading last version of ${ORIGIN_PLATFORM} ${KVER}+ rp-lkms.zip, Stop Booting...\n"
        exit 99
    fi

    TAG="${LATESTURL##*/}"
    echo "TAG is ${TAG}"        
    STATUS=`curl --connect-timeout 5 -skL -w "%{http_code}" "${PROXY}https://github.com/PeterSuh-Q3/redpill-lkm${v}/releases/download/${TAG}/rp-lkms.zip" -o "/tmp/rp-lkms${v}.zip"`

    if [ "${ORIGIN_PLATFORM}" = "epyc7002" ]||[ "${ORIGIN_PLATFORM}" = "v1000nk" ]; then
        unzip /tmp/rp-lkms${v}.zip rp-${ORIGIN_PLATFORM}-${major}.${minor}-${KVER}-prod.ko.gz -d /tmp >/dev/null 2>&1
        gunzip -f /tmp/rp-${ORIGIN_PLATFORM}-${major}.${minor}-${KVER}-prod.ko.gz >/dev/null 2>&1
        cp -vf /tmp/rp-${ORIGIN_PLATFORM}-${major}.${minor}-${KVER}-prod.ko /root/redpill.ko
    else
        unzip /tmp/rp-lkms${v}.zip rp-${ORIGIN_PLATFORM}-${KVER}-prod.ko.gz -d /tmp >/dev/null 2>&1
        gunzip -f /tmp/rp-${ORIGIN_PLATFORM}-${KVER}-prod.ko.gz >/dev/null 2>&1
        cp -vf /tmp/rp-${ORIGIN_PLATFORM}-${KVER}-prod.ko /root/redpill.ko
    fi    

    if [ -f /root/redpill.ko ] && [ -n $(strings /root/redpill.ko | grep -i $model | head -1) ]; then
        echo "Copying redpill.ko module to ramdisk"
        cp /root/redpill.ko /root/rd.temp/usr/lib/modules/rp.ko
    else
        echo "Module does not contain platform information for ${model}"
    fi

    [ -f /root/rd.temp/usr/lib/modules/rp.ko ] && echo "Redpill module is in place"
}

function getstaticmodule() {
    redpillextension="https://github.com/pocopico/rp-ext/raw/main/redpill${redpillmake}/rpext-index.json"
    SYNOMODEL="$(echo $model | sed -e 's/+/p/g' | tr '[:upper:]' '[:lower:]')_${buildnumber}"

    cd /root

    echo "Removing any old redpill.ko modules"
    [ -f /root/redpill.ko ] && rm -f /root/redpill.ko

    extension=$(curl --insecure --silent --location "$redpillextension")

    echo "Looking for redpill for : $SYNOMODEL"

    release=$(echo $extension | jq -r -e --arg SYNOMODEL $SYNOMODEL '.releases[$SYNOMODEL]')
    files=$(curl --insecure --silent --location "$release" | jq -r '.files[] .url')

    for file in $files; do
        echo "Getting file $file"
        curl --insecure --silent -O $file
        if [ -f redpill*.tgz ]; then
            echo "Extracting module"
            gunzip redpill*.tgz
            tar xf redpill*.tar
            rm redpill*.tar
            strip --strip-debug redpill.ko
        fi
    done

    if [ -f /root/redpill.ko ] && [ -n $(strings /root/redpill.ko | grep -i $model | head -1) ]; then
        echo "Copying redpill.ko module to ramdisk"
        cp /root/redpill.ko /root/rd.temp/usr/lib/modules/rp.ko
    else
        echo "Module does not contain platform information for ${model}"
    fi

    [ -f /root/rd.temp/usr/lib/modules/rp.ko ] && echo "Redpill module is in place"

}

function _set_conf_kv() {
    # Delete
    if [ -z "$2" ]; then
        sed -i "$3" -e "s/^$1=.*$//"
        return 0
    fi

    # Replace
    if grep -q "^$1=" "$3"; then
        sed -i "$3" -e "s\"^$1=.*\"$1=\\\"$2\\\"\""
        return 0
    fi

    # Add if doesn't exist
    echo "$1=\"$2\"" >>$3
}

function patchkernel() {

    echo "Patching Kernel"

    /root/tools/bzImage-to-vmlinux.sh /mnt/tcrp-p2/zImage /root/vmlinux >log 2>&1 >/dev/null
    /root/tools/kpatch /root/vmlinux /root/vmlinux-mod >log 2>&1 >/dev/null
    /root/tools/vmlinux-to-bzImage.sh /root/vmlinux-mod /mnt/tcrp/zImage-dsm >/dev/null

    [ -f /mnt/tcrp/zImage-dsm ] && echo "Kernel Patched, sha256sum : $(sha256sum /mnt/tcrp/zImage-dsm | awk '{print $1}')"

}

function extractramdisk() {

    temprd="/root/rd.temp/"

    echo "Extracting ramdisk to $temprd"

    [ ! -d $temprd ] && mkdir $temprd
    cd $temprd

    if [ $(od /mnt/tcrp-p2/rd.gz | head -1 | awk '{print $2}') == "000135" ]; then
        echo "Ramdisk is compressed"
        xz -dc /mnt/tcrp-p2/rd.gz 2>/dev/null | cpio -idm >/dev/null 2>&1
    else
        cat /mnt/tcrp-p2/rd.gz | cpio -idm 2>&1 >/dev/null
    fi

    if [ -f $temprd/etc/VERSION ]; then
        . $temprd/etc/VERSION
        echo "Extracted ramdisk VERSION : ${major}.${minor}.${micro}-${buildnumber} U${smallfixnumber}"
    else
        echo "ERROR, Couldnt read extracted file version"
        exit 99
    fi

    version="${major}.${minor}.${micro}-${buildnumber}"
    smallfixnumber="${smallfixnumber}"

}

function patchramdisk() {

    if [ ! -n "$IP" ]; then
        msgalert "The patch cannot proceed because there is no IP yet !!!! \n"
        exit 99
    fi

    extractramdisk

    temprd="/root/rd.temp"
    CONFIG_PATH="/root/config/$ORIGIN_PLATFORM/$version/config.json"
    
    RAMDISK_PATCH=$(cat ${CONFIG_PATH} | jq -r -e ' .patches .ramdisk')
    SYNOINFO_PATCH=$(cat ${CONFIG_PATH} | jq -r -e ' .synoinfo')
    SYNOINFO_USER=$(cat /mnt/tcrp/user_config.json | jq -r -e ' .synoinfo')
    RAMDISK_COPY=$(cat ${CONFIG_PATH} | jq -r -e ' .extra .ramdisk_copy')
    RD_COMPRESSED=$(cat ${CONFIG_PATH} | jq -r -e ' .extra .compress_rd')
    echo "Patching RamDisk"

    PATCHES="$(echo $RAMDISK_PATCH | jq . | sed -e 's/@@@COMMON@@@/\/root\/config\/_common/' | grep config | sed -e 's/"//g' | sed -e 's/,//g')"

    echo "Patches to be applied : $PATCHES"

    cd $temprd
    . $temprd/etc/VERSION
    for patch in $PATCHES; do
        echo "Applying patch $patch in dir $PWD"
        patch -p1 <$patch
    done

    # Patch /sbin/init.post
    grep -v -e '^[\t ]*#' -e '^$' "/root/patch/config-manipulators.sh" >"/root/rp.txt"
    sed -e "/@@@CONFIG-MANIPULATORS-TOOLS@@@/ {" -e "r /root/rp.txt" -e 'd' -e '}' -i "${temprd}/sbin/init.post"
    rm "/root/rp.txt"

    touch "/root/rp.txt"

    echo "Applying model synoinfo patches"

    while IFS=":" read KEY VALUE; do
        if [ -z "$VALUE" ]; then
            continue
        fi
        KEY="$(echo $KEY | xargs)" && VALUE="$(echo $VALUE | xargs)"
        _set_conf_kv "${KEY}" "${VALUE}" $temprd/etc/synoinfo.conf
        echo "_set_conf_kv \"${KEY}\" \"${VALUE}\" /tmpRoot/etc/synoinfo.conf" >>"/root/rp.txt"
        echo "_set_conf_kv \"${KEY}\" \"${VALUE}\" /tmpRoot/etc.defaults/synoinfo.conf" >>"/root/rp.txt"
    done <<<$(echo $SYNOINFO_PATCH | jq . | grep ":" | sed -e 's/"//g' | sed -e 's/,//g')

    echo "Applying user synoinfo settings"

    while IFS=":" read KEY VALUE; do
        if [ -z "$VALUE" ]; then
            continue
        fi
        KEY="$(echo $KEY | xargs)" && VALUE="$(echo $VALUE | xargs)"
        _set_conf_kv "${KEY}" "${VALUE}" $temprd/etc/synoinfo.conf
        echo "_set_conf_kv \"${KEY}\" \"${VALUE}\" /tmpRoot/etc/synoinfo.conf" >>"/root/rp.txt"
        echo "_set_conf_kv \"${KEY}\" \"${VALUE}\" /tmpRoot/etc.defaults/synoinfo.conf" >>"/root/rp.txt"
    done <<<$(echo $SYNOINFO_USER | jq . | grep ":" | sed -e 's/"//g' | sed -e 's/,//g')

    sed -e "/@@@CONFIG-GENERATED@@@/ {" -e "r /root/rp.txt" -e 'd' -e '}' -i "${temprd}/sbin/init.post"
    rm /root/rp.txt

    echo "Copying extra ramdisk files "

    while IFS=":" read SRC DST; do
        echo "Source :$SRC Destination : $DST"
        cp -f $SRC $DST
    done <<<$(echo $RAMDISK_COPY | jq . | grep "COMMON" | sed -e 's/"//g' | sed -e 's/,//g' | sed -e 's/@@@COMMON@@@/\/root\/config\/_common/')

    echo "Adding precompiled redpill module"
    getredpillko
    #getstaticmodule

    echo "Adding custom.gz or initrd-dsm to image"
    cd $temprd
    # 0.1.0m Recycle initrd-dsm instead of custom.gz (extract /exts), The priority starts from custom.gz
    if [ -f /mnt/tcrp/custom.gz ]; then
        echo "Found custom.gz, so extract from custom.gz " 
        if [ -f /mnt/tcrp/custom.gz ]; then
            cat /mnt/tcrp/custom.gz | cpio -idm >/dev/null 2>&1
        else
            cat /mnt/tcrp-p1/custom.gz | cpio -idm >/dev/null 2>&1
        fi
    else
        echo "Not found custom.gz, so extract from initrd-dsm " 
        cat /mnt/tcrp/initrd-dsm | cpio -idm "*exts*" >/dev/null 2>&1
        cat /mnt/tcrp/initrd-dsm | cpio -idm "*modprobe*"  >/dev/null 2>&1
        cat /mnt/tcrp/initrd-dsm | cpio -idm "*rp.ko*"  >/dev/null 2>&1
    fi

    for script in $(find /root/rd.temp/exts/ | grep ".sh"); do chmod +x $script; done
    chmod +x $temprd/usr/sbin/modprobe

    # Reassembly ramdisk
    echo "Reassempling ramdisk"
    if [ "${RD_COMPRESSED}" == "true" ]; then
        (cd "${temprd}" && find . | cpio -o -H newc -R root:root | xz -9 --format=lzma >"/root/initrd-dsm") >/dev/null 2>&1 >/dev/null
    else
        (cd "${temprd}" && find . | cpio -o -H newc -R root:root >"/root/initrd-dsm") >/dev/null 2>&1
    fi
    [ -f /root/initrd-dsm ] && echo "Patched ramdisk created $(ls -l /root/initrd-dsm)"

    echo "Copying file to ${LOADER_DISK}"

    cp -f /root/initrd-dsm /mnt/tcrp

    cd /root && rm -rf $temprd

    origrdhash=$(sha256sum /mnt/tcrp-p2/rd.gz | awk '{print $1}')
    origzimghash=$(sha256sum /mnt/tcrp-p2/zImage | awk '{print $1}')
    version="${major}.${minor}.${micro}-${buildnumber}"
    smallfixnumber="${smallfixnumber}"

    updateuserconfigfield "general" "rdhash" "$origrdhash"
    updateuserconfigfield "general" "zimghash" "$origzimghash"
    updateuserconfigfield "general" "version" "${major}.${minor}.${micro}-${buildnumber}"
    updateuserconfigfield "general" "smallfixnumber" "${smallfixnumber}"
    updategrubconf

}

function setgrubdefault() {

    echo "Setting default boot entry to $1"
    sed -i "s/set default=\"[0-9]\"/set default=\"$1\"/g" /mnt/tcrp-p1/boot/grub/grub.cfg
}

function updateuserconfigfile() {

    backupfile="$userconfigfile.$(date +%Y%b%d)"
    jsonfile=$(jq . $userconfigfile)

    if [ "$(echo $jsonfile | jq '.general .usrcfgver')" = "null" ] || [ "$(echo $jsonfile | jq -r -e '.general .usrcfgver')" != "$BOOTVER" ]; then
        echo -n "User config file needs update, updating -> "
        jsonfile=$([ "$(echo $jsonfile | jq '.general .usrcfgver')" = "null" ] || [ "$(echo $jsonfile | jq -r -e '.general .usrcfgver')" != "$BOOTVER" ] && echo $jsonfile | jq ".general |= . + { \"usrcfgver\":\"$BOOTVER\" }" || echo $jsonfile | jq .)
        jsonfile=$([ "$(echo $jsonfile | jq '.general .redpillmake')" = "null" ] && echo $jsonfile | jq '.general |= . + { "redpillmake":"dev" }' || echo $jsonfile | jq .)
        jsonfile=$([ "$(echo $jsonfile | jq '.general .friendautoupd')" = "null" ] && echo $jsonfile | jq '.general |= . + { "friendautoupd":"true" }' || echo $jsonfile | jq .)
        jsonfile=$([ "$(echo $jsonfile | jq '.general .hidesensitive')" = "null" ] && echo $jsonfile | jq '.general |= . + { "hidesensitive":"false" }' || echo $jsonfile | jq .)
        jsonfile=$([ "$(echo $jsonfile | jq '.ipsettings')" = "null" ] && echo $jsonfile | jq '. |= .  + {"ipsettings": { "ipset":"", "ipaddr":"", "ipgw":"", "ipdns":"", "ipproxy":"" }}' || echo $jsonfile | jq .)
        cp $userconfigfile $backupfile
        echo $jsonfile | jq . >$userconfigfile && echo "Done" || echo "Failed"

    fi

}

function updategrubconf() {

    curgrubver="$(grep menuentry /mnt/tcrp-p1/boot/grub/grub.cfg | head -1 | awk '{print $6}')"
    curgrubsmall="$(grep menuentry /mnt/tcrp-p1/boot/grub/grub.cfg | head -1 | awk '{print $8}')"
    echo "Updating grub version values from: $curgrubver U$curgrubsmall to $version U$smallfixnumber"
    sed -i "s/$curgrubver/$version/g" /mnt/tcrp-p1/boot/grub/grub.cfg
    sed -i "s/Update $curgrubsmall/Update $smallfixnumber/g" /mnt/tcrp-p1/boot/grub/grub.cfg

}

function updateuserconfigfield() {

    block="$1"
    field="$2"
    value="$3"

    if [ -n "$1 " ] && [ -n "$2" ]; then
        jsonfile=$(jq ".$block+={\"$field\":\"$value\"}" $userconfigfile)
        echo $jsonfile | jq . >$userconfigfile
    else
        echo "No values to update specified"
    fi
}

function checkupgrade() {

    if [ ! -f /mnt/tcrp-p2/rd.gz ]; then
        TEXT "ERROR ! /mnt/tcrp-p2/rd.gz file not found, stopping boot process"
        exit 99
    fi
    if [ ! -f /mnt/tcrp-p2/zImage ]; then
        TEXT "ERROR ! /mnt/tcrp-p2/zImage file not found, stopping boot process"
        exit 99
    fi

    origrdhash=$(sha256sum /mnt/tcrp-p2/rd.gz | awk '{print $1}')
    origzimghash=$(sha256sum /mnt/tcrp-p2/zImage | awk '{print $1}')
    rdhash="$(jq -r -e '.general .rdhash' $userconfigfile)"
    zimghash="$(jq -r -e '.general .zimghash' $userconfigfile)"

    if [ "$loadermode" == "JOT" ]; then    
        if [ "${BUS}" = "usb" ]; then
            msgnormal "Setting default boot entry to JOT USB\n"
            setgrubdefault 2
        else
            msgnormal "Setting default boot entry to JOT SATA\n"
            setgrubdefault 3
        fi        
    fi

    echo -n $(TEXT "Detecting upgrade : ")

    if [ "$rdhash" = "$origrdhash" ]; then
        msgnormal "Ramdisk OK ! "
    else
        msgwarning "Ramdisk upgrade has been detected. \n"
        [ -z "$IP" ] && getip
        if [ -n "$IP" ]; then
            patchramdisk 2>&1 | awk '{ print strftime("%Y-%m-%d %H:%M:%S"), $0; }' >>$FRIENDLOG
            smallfixnumber="$(jq -r -e '.general .smallfixnumber' $userconfigfile)"
            echo -ne "Smallfixnumber version changed after Ramdisk Patch, Build : $(msgnormal "$version"), Update : $(msgnormal "$smallfixnumber")\n"            
        else
            msgalert "The patch cannot proceed because there is no IP yet !!!! \n"
            exit 99
        fi
    fi

    if [ "$zimghash" = "$origzimghash" ]; then
        msgnormal "zImage OK ! \n"
    else
        msgwarning "zImage upgrade has been detected. \n"
        patchkernel 2>&1 | awk '{ print strftime("%Y-%m-%d %H:%M:%S"), $0; }' >>$FRIENDLOG
   
        if [ "$loadermode" == "JOT" ]; then
            msgwarning "Ramdisk upgrade and zImage upgrade for JOT completed successfully!\n"
            TEXT "A reboot is required. Press any key to reboot..."
            read answer
            reboot
        fi
    fi
    
}

function mountall() {

    # get SHR or NORMAL
    getloadertype
    #echo "LOADER_DISK = ${LOADER_DISK}"

    BUS=$(getBus "${LOADER_DISK}")

    if [ -z "${LOADER_DISK}" ]; then
        TEXT "Not Supported Loader BUS Type, program Exit!!!"
        exit 99
    fi
    
    [ "${BUS}" = "nvme" ] && LOADER_DISK="${LOADER_DISK}p"
    [ "${BUS}" = "mmc"  ] && LOADER_DISK="${LOADER_DISK}p"    

    [ ! -d /mnt/tcrp ] && mkdir /mnt/tcrp
    [ ! -d /mnt/tcrp-p1 ] && mkdir /mnt/tcrp-p1
    [ ! -d /mnt/tcrp-p2 ] && mkdir /mnt/tcrp-p2

    echo "LOADER_DISK = ${LOADER_DISK}"

    if [ "${LDTYPE}" = "SHR" ]; then
      echo "Found Syno Boot Injected Partition !!!"
      SHR_EX_TEXT=" (SynoBoot Injected into Synodisk)"
      p1="4"
      p2="6"
      p3="7"
    else
      SHR_EX_TEXT=""
      p1="1"
      p2="2"
      p3="3"
    fi

    [ "$(mount | grep ${LOADER_DISK}${p1} | wc -l)" = "0" ] && mount /dev/${LOADER_DISK}${p1} /mnt/tcrp-p1
    [ "$(mount | grep ${LOADER_DISK}${p2} | wc -l)" = "0" ] && mount /dev/${LOADER_DISK}${p2} /mnt/tcrp-p2 
    [ "$(mount | grep ${LOADER_DISK}${p3} | wc -l)" = "0" ] && mount /dev/${LOADER_DISK}${p3} /mnt/tcrp

    if [ "$(mount | grep /mnt/tcrp-p1 | wc -l)" = "0" ]; then
        echo "Failed mount /dev/${LOADER_DISK}${p1} to /mnt/tcrp-p1, stopping boot process"
        exit 99
    fi

    if [ "$(mount | grep /mnt/tcrp-p2 | wc -l)" = "0" ]; then
        echo "Failed mount /dev/${LOADER_DISK}${p2} to /mnt/tcrp-p2, stopping boot process"
        exit 99
    fi

    if [ "$(mount | grep /mnt/tcrp | wc -l)" = "0" ]; then
        echo "Failed mount /dev/${LOADER_DISK}${p3} to /mnt/tcrp, stopping boot process"
        exit 99
    fi

}

function readconfig() {

    if [ -f $userconfigfile ]; then
        model="$(jq -r -e '.general .model' $userconfigfile)"
        if [ -z "$model" ]; then
            TEXT "model is not resolved. Please check the /mnt/tcrp/user_config.json file. stopping boot process"
            exit 99
        fi        
        version="$(jq -r -e '.general .version' $userconfigfile)"
        if [ -z "$version" ]; then
            TEXT "Build version is not resolved. Please check the /mnt/tcrp/user_config.json file. stopping boot process"
            exit 99
        fi        
        smallfixnumber="$(jq -r -e '.general .smallfixnumber' $userconfigfile)"
        if [ -z "$smallfixnumber" ]; then
            TEXT "Update(smallfixnumber) is not resolved. Please check the /mnt/tcrp/user_config.json file."
        #    exit 99
        fi        
        redpillmake="$(jq -r -e '.general .redpillmake' $userconfigfile)"
        friendautoupd="$(jq -r -e '.general .friendautoupd' $userconfigfile)"
        hidesensitive="$(jq -r -e '.general .hidesensitive' $userconfigfile)"
        serial="$(jq -r -e '.extra_cmdline .sn' $userconfigfile)"
        if [ -z "$serial" ]; then
            TEXT "serial is not resolved. Please check the /mnt/tcrp/user_config.json file. stopping boot process"
            exit 99
        fi        
        rdhash="$(jq -r -e '.general .rdhash' $userconfigfile)"
        zimghash="$(jq -r -e '.general .zimghash' $userconfigfile)"
        mac1="$(jq -r -e '.extra_cmdline .mac1' $userconfigfile)"
        if [ -z "$mac1" ]; then
            TEXT "mac1 is not resolved. Please check the /mnt/tcrp/user_config.json file. stopping boot process"
            exit 99
        fi        
        mac2="$(jq -r -e '.extra_cmdline .mac2' $userconfigfile)"
        mac3="$(jq -r -e '.extra_cmdline .mac3' $userconfigfile)"
        mac4="$(jq -r -e '.extra_cmdline .mac4' $userconfigfile)"
    	mac5="$(jq -r -e '.extra_cmdline .mac5' $userconfigfile)"
     	mac6="$(jq -r -e '.extra_cmdline .mac6' $userconfigfile)"
      	mac7="$(jq -r -e '.extra_cmdline .mac7' $userconfigfile)"
        mac8="$(jq -r -e '.extra_cmdline .mac8' $userconfigfile)"
        staticboot="$(jq -r -e '.general .staticboot' $userconfigfile)"
        dmpm="$(jq -r -e '.general.devmod' $userconfigfile)"
        loadermode="$(jq -r -e '.general.loadermode' $userconfigfile)"
        ucode=$(jq -r -e '.general.ucode' "$userconfigfile")
        tz=$(echo $ucode | cut -c 4-)

        usrdisks=$(jq -r -e '.general.diskcount' "$userconfigfile")
    	chkdisk="false"
    	chkdisk=$(jq -r -e '.general.check_diskcnt' "$userconfigfile")

        export LANG=${ucode}.UTF-8
        export LC_ALL=${ucode}.UTF-8
  
    else
        echo "ERROR ! User config file : $userconfigfile not found"
    fi

    [ -z "$redpillmake" ] || [ "$redpillmake" = "null" ] && echo "redpillmake setting not found while reading $userconfigfile, defaulting to dev" && redpillmake="dev"

}

function initialize() {

    # Mount loader disk
    [ -z "${LOADER_DISK}" ] && mountall

    # Read Configuration variables
    readconfig

    # Update user config file to latest version
    updateuserconfigfile

    ORIGIN_PLATFORM=$(cat /mnt/tcrp-p1/GRUB_VER | grep PLATFORM | cut -d "=" -f2 | tr '[:upper:]' '[:lower:]' | sed 's/"//g')

}

case $1 in

checkupgrade)
    initialize
    checkupgrade
    ;;
*)
    initialize
    ;;

esac
