#!/bin/bash
#
# Author : PeterSuh-Q3
# Date : 250702
# User Variables :
###############################################################################

##### INCLUDES #####################################################################################################
source /root/menufunc.h
#####################################################################################################

BOOTVER="0.1.3m"
FRIENDLOG="/mnt/tcrp/friendlog.log"
AUTOUPDATES="1"
userconfigfile=/mnt/tcrp/user_config.json

# Apply i18n
export TEXTDOMAINDIR="/root/lang"
alias TEXT='gettext "msg"'
shopt -s expand_aliases

function history() {
    cat <<EOF
    --------------------------------------------------------------------------------------
    0.0.1 Initial Release
    0.0.2 Added the option to disable TCRP Friend auto update. Default if true.
    0.0.3 Added smallfixnumber to display current update version on boot
    0.0.4 Testing 5.x, fixed typo and introduced user config file update and backup
    0.0.5 Added menu function to edit CMDLINE of user_config.json
    0.0.6 Added Getty Console to solve trouble
    0.0.6a Fix Intel CpuFreq Performence Management
    0.0.6b Added mountall success check routine
    0.0.6c Add CONFIG_MQ_IOSCHED_DEADLINE=y, CONFIG_MQ_IOSCHED_KYBER=y, CONFIG_IOSCHED_BFQ=y, CONFIG_BFQ_GROUP_IOSCHED=y
           restore CpuFreq performance tuning settings ( from 0.0.6a )
    0.0.6d Processing without errors related to synoinfo.conf while processing Ramdisk upgrade
    0.0.6e Removed "No space left on device" when copying /mnt/tcrp-p1/rd.gz file during Ramdisk upgrade
    0.0.6f Add Postupdate boot entry to Grub Boot for Jot Postupdate to utilize FRIEND's Ramdisk upgrade
    0.0.6g Recompile for DSM 7.2.0-64551 RC support
    0.0.7  removed custom.gz from partition 1, added static boot option
    0.0.8  Added the detection of EFI and the addition of withefi option to cmdline
           Enhanced the synoinfo key reading to accept multiword keys
           Fixed an a leading space in the synoinfo key reading
    0.0.8a Updated configs to 64570 U1
    0.0.8b Remove Getty Console (apply debug util instead, logs are stored in /mnt/sd#1/logs/jr)
    0.0.8c Change the Github repository used by getstatic module(): The reason is redpill.ko KP issue for Denverton found when patching ramdisk
    0.0.8d Updated configs to remove fake rss info
    0.0.8e Updated configs to remove DSM auto-update loopback block
    0.0.8f dom_szmax 1GB Restore from static size to dynamic setting
    0.0.8g Added retry processing when downloading rp-lkms.zip of ramdisk patch fails
    0.0.8h When performing Ramdisk Patch, check the IP grant status before proceeding. Thanks ExpBox.
    0.0.9  Added IP detection function on multiple ethernet devices
    0.0.9a Added friend kernel 5.15.26 compatible NIC firmware in bulk
           Added ./boot.sh update (new function)
    0.0.9b Updated to add support for 7.2.1-69057
    0.0.9c Added QR code image for port 5000 access
    0.0.9d Bug fixes for Kernel 5 SA6400 Ramdisk patch
    0.0.9e Maintenance of config/_common/v7*/ramdisk-002-init patch for ramdisk patch
    0.0.9f Added new model configs DS1522+(r1000), DS220+(geminilake), DS2419+(denverton), DS423+(geminilake), DS718+(apollolake), RS2423+(v1000)
    0.0.9g Bug fixes for Kernel 5 SA6400-7.2.1-69057 Ramdisk patch #2
    0.0.9h Adjust the partition priority of custom.gz to be used when patching ramdisk (use from the 3rd partition)
    0.0.9i Bug fixes for Kernel 5 SA6400 Kernel patch
    0.0.9j Added MAC address remapping function referring to user_config.json
    0.0.9k Switch to local storage when rp-lkms.zip download fails when ramdisk patch occurs without internet
    0.0.9l Added Reset DSM Password function
    0.0.9m If no internet, skip installing the Python library for QR codes
    0.1.0  friend kernel version up from 5.15.26 to 6.4.16
    0.1.0a Added IP detection function for all NICs
    0.1.0b Added IP detection function for all NICs (Fix bugs)
    0.1.0c Fix First IP CR Issue
    0.1.0d Fix Some H/W Display Info, Add skip_vender_mac_interfaces cmdline to enable DSM's dhcp to use the correct mac and ip
    0.1.0e Add Re-install DSM wording to force_junior
    0.1.0f Fixed module name notation error in Realtek derived device [ex) r8125]
    0.1.0g Fix bug of 0.1.0f
    0.1.0h Add process to abort boot if corrupted user_config.json is used
    0.1.0i Remove smallfixnumber check routine in user_config.json
    0.1.0j Remove skip_vender_mac_interfaces and panic cmdline (SAN MANAGER Cause of damage)
    0.1.0k Added timestamp recording function before line in /mnt/tcrp/friendlog.log file.
    0.1.0l Modified the kexec option from -a (memory) to -f (file) to accurately load the patched initrd-dsm.
    0.1.0m Recycle initrd-dsm instead of custom.gz (extract /exts), The priority starts from custom.gz
    0.1.0n When a loader is inserted into syno disk /dev/sda and /dev/sdb, change to additionally mount partitions 1,2 and 3 to /dev/sda5,/dev/sda6 and /dev/sdb5.
    0.1.0o Added RedPill bootloader hard disk porting function
    0.1.0p Added priority search for USB or VMDK bootloader over bootloader injected into HDD
    0.1.0q Added support for SHR type to HDD for bootloader injection. 
           synoboot3 unified to use partition number 4 instead of partition number 5 (1 BASIC + 1 SHR required)
    0.1.0r Fix bug of 0.1.0q (Fix typo for partition number 4)
    0.1.0s Force the dom_szmax limit of the injected bootloader to be 16GB
    0.1.0t Supports bootloader injection with SHR disk only
           dom_szmax=32GB (limit size of the injected bootloader)
    0.1.0u Loader support bus type expansion (mmc, NVMe, etc.)
    0.1.0v Improved functionality to skip non-bootloader devices
    0.1.0w Improved setnetwork function for using static IP
    0.1.0x Multilingual explanation i18n support (Priority given to German, Spanish, French, and Korean)
    0.1.0y Multilingual explanation i18n support (Added Japanese, Chinese, Russian, Brazilian, and Italian)
    0.1.0z Multilingual explanation i18n support (Added Arabic, Hindi, Hungarian, Indonesian, and Turkish)
    0.1.1a Extra menu bug fixed
    0.1.1b Display smallfixnumber version changed after Ramdisk patch
    0.1.1c Fix Added cmdline netif_num missing check function and corrected URL error (thanks EM10)
    0.1.1d Multilingual explanation i18n support (Added Amharic-Ethiopian and Thai)
    0.1.1e Update config for DS218+ and SA6400-7.1.1
    0.1.1f Adjust Grub bootentry default after PostUpdate for jot mode
    0.1.1g Sort netif order by bus-id order (Synology netif sorting method)
    0.1.1h Fixed error displaying information for USB type NICs
    0.1.1i Added a feature to check whether the pre-counted number of disks matches (Optional)
    0.1.1j SA6400(epyc7002) is integrated from lkm5 to lkm(lkm 24.9.8), affected by ramdisk patch.
    0.1.1k Enable mmc (SD Card) recognition
    0.1.1l Added manual update feature to specified version, added disable/enable automatic update feature
    0.1.1m Expanded MAC address support from 4 to 8, Add skip_vender_mac_interfaces cmdline again
    0.1.1n Remove skip_vender_mac_interfaces cmdline ( Issue with not being able to use the changed mac address )
    0.1.1o Added features for distribution of xTCRP (Tinycore Linux stripped down version)
    0.1.1p Fix xTCRP user tc permissions issue
    0.1.1q Handling menu.sh and additional shell script aliases in xTCRP
    0.1.1r Improved getloaderdisk() processing, displayed the number of NVMe disks
    0.1.1s Add Mellanox MLX4(InfiniBand added), MLX5 modules
    0.1.1t Added platform-specific integrated config.json when patching ramdisk Added reference function 
    0.1.1u Renewal of SynoDisk bootloader injection function
    0.1.1v SynoDisk with Bootloader Injection Supports NVMe DISK
    0.1.1w SynoDisk with Bootloader Injection Supports Single SHR DISK
    0.1.1x NVMe/MMC type bootloader bug fix of mountall()
    0.1.1y SynoDisk with bootloader injection uses UUID 8765-4321 instead of 6234-C863
    0.1.1z Changed to load the default loader first rather than the one injected into Synodisk
    0.1.2a Bugfix bad array subscript of getloadertype()
    0.1.2b Update config for DS3615xs (bromolow)
    0.1.2c Fix xTCRP web console URL guidance and error message output issues
    0.1.2d Change the path referenced by source to /root/menufunc.h
    0.1.2e Fix boot failure error when bootloader has more than 4 partitions
    0.1.3a friend kernel version up from 6.4.16 to 6.6.22 (expecting mmc module improvements)
    0.1.3b avoton (DS1515+ kernel 3) support started
    0.1.3c cedarview (DS713+ kernel 3) support started
    0.1.3d v1000nk (DS925+ kernel 5) support started
    0.1.3e When processing "lsblk -nro UUID" in the getloadertype() function, 
           limit the search to only the bootloader partition.
    0.1.3f Added delay processing function for recognition of eMMC module
    0.1.3g Change the way mmc devices are recognized
    0.1.3h Add mev command line option for vmtools addon
    0.1.3i Activate build root openssl bin for DSM password make and renewal Reset(Change) DSM Password function
           Add menu for "Add New DSM User"
    0.1.3j Resize QR CODE
    0.1.3k Add config of r1000nk, geminilakenk
    0.1.3l QR Code is activated regardless of internet connection, Improvement of Internet Check Method
    0.1.3m Enable FRIEND Kernel on HP N36L/N40L/N54L (Supports Older AMD CPUs)
    
    Current Version : ${BOOTVER}
    --------------------------------------------------------------------------------------
EOF
}

function showlastupdate() {
    cat <<EOF
0.1.0  friend kernel version up from 5.15.26 to 6.4.16
0.1.1l Added manual update feature to specified version, added disable/enable automatic update feature
      ( usage : ./boot.sh update v0.1.1j | ./boot.sh autoupdate off | ./boot.sh autoupdate on )
0.1.1y SynoDisk with bootloader injection uses UUID 8765-4321 instead of 6234-C863
0.1.3a friend kernel version up from 6.4.16 to 6.6.22 (expecting mmc module improvements)
0.1.3d v1000nk (DS925+ kernel 5) support started
0.1.3f Added delay processing function for recognition of eMMC module
0.1.3i Activate build root openssl bin for DSM password make and renewal Reset(Change) DSM Password function
       Add menu for "Add New DSM User"
0.1.3k Add config of r1000nk, geminilakenk
0.1.3l QR Code is activated regardless of internet connection, Improvement of Internet Check Method
0.1.3m Enable FRIEND Kernel on HP N36L/N40L/N54L (Supports Older AMD CPUs)
       
EOF
}

function version() {
    shift 1
    echo $BOOTVER
    [ "$1" == "history" ] && history
}

function msgalert() {
    echo -en "\033[1;31m$1\033[0m"
}
function msgnormal() {
    echo -en "\033[1;32m$1\033[0m"
}
function msgwarning() {
    echo -en "\033[1;33m$1\033[0m"
}
function msgblue() {
    echo -en "\033[1;34m$1\033[0m"
}
function msgpurple() {
    echo -en "\033[1;35m$1\033[0m"
}
function msgcyan() {
    echo -en "\033[1;36m$1\033[0m"
}

function check_internet() {
  ping -c 1 -W 1 8.8.8.8 > /dev/null 2>&1
  return $?
}

function checkinternet() {

    echo -n $(TEXT "Detecting Internet -> ")
    # Record the start time.
    start_time=$(date +%s)
    while true; do
      if check_internet; then
        INTERNET="ON"
        msgwarning " OK!\n"
        break
      fi
      # Calculate the elapsed time and exit the loop if it exceeds 15 seconds.
      current_time=$(date +%s)
      elapsed=$(( current_time - start_time ))
      if [ $elapsed -ge 20 ]; then
        INTERNET="OFF"
        echo -e "$(msgwarning "$(TEXT "No internet found, Skip updating friends and installing Python libraries for QR codes!")")"
        break
      fi
      sleep 2
      msgwarning "."
    done

}

function changeautoupdate {
    if [ -z "$1" ]; then
      echo -en "\r$(msgalert "$(TEXT "There is no on or off parameter.!!!")")\n"
      exit 99
    elif [ "$1" != "on" ] && [ "$1" != "off" ]; then
      echo -en "\r$(msgalert "$(TEXT "There is no on or off parameter.!!!")")\n"
      exit 99
    fi

    backupfile="$userconfigfile.$(date +%Y%b%d)"
    jsonfile=$(jq . $userconfigfile)
    
    echo -n "friendautoupd on User config file needs update, updating -> "
    if [ "$1" = "on" ]; then
        jsonfile=$(echo $jsonfile | jq '.general |= . + { "friendautoupd":"true" }' || echo $jsonfile | jq .)
    else
        jsonfile=$(echo $jsonfile | jq '.general |= . + { "friendautoupd":"false" }' || echo $jsonfile | jq .)
    fi
    cp $userconfigfile $backupfile
    echo $jsonfile | jq . >$userconfigfile && echo "Done" || echo "Failed"
    
    cat $userconfigfile | grep friendautoupd

}

function upgradefriend() {

    if [ "${LDTYPE}" = "SHR" ]; then
      chgpart="-p1"
    else
      chgpart="" 
    fi
    
    if [ ! -z "$IP" ]; then

        if [ "${friendautoupd}" = "false" ]; then
            echo -en "\r$(msgwarning "$(TEXT "TCRP Friend auto update disabled")")\n"
            return
        else
            friendwillupdate="1"
        fi

        echo -n $(TEXT "Checking for latest friend -> ")
        URL=$(curl --connect-timeout 15 -s --insecure -L https://api.github.com/repos/PeterSuh-Q3/tcrpfriend/releases/latest | jq -r -e .assets[].browser_download_url | grep chksum)
        [ -n "$URL" ] && curl -s --insecure -L $URL -O

        if [ -f chksum ]; then
            FRIENDVERSION="$(grep VERSION chksum | awk -F= '{print $2}')"
            BZIMAGESHA256="$(grep bzImage-friend chksum | awk '{print $1}')"
            INITRDSHA256="$(grep initrd-friend chksum | awk '{print $1}')"
            if [ "$(sha256sum /mnt/tcrp${chgpart}/bzImage-friend | awk '{print $1}')" = "$BZIMAGESHA256" ] && [ "$(sha256sum /mnt/tcrp${chgpart}/initrd-friend | awk '{print $1}')" = "$INITRDSHA256" ]; then
                msgnormal "OK, latest \n"
            else
                if [ "${FRIENDVERSION}" = "v0.1.0" ]; then
                    msgwarning "Remove vga=791 parameter from grub.cfg friend boot entry to prevent console dead.\n"
                    sed -i "s#vga=791 net#net#g" /mnt/tcrp-p1/boot/grub/grub.cfg
                fi
                msgwarning "Found new version, bringing over new friend version : $FRIENDVERSION \n"
                URLS=$(curl --insecure -s https://api.github.com/repos/PeterSuh-Q3/tcrpfriend/releases/latest | jq -r ".assets[].browser_download_url")
                for file in $URLS; do curl --insecure --location --progress-bar "$file" -O; done
                FRIENDVERSION="$(grep VERSION chksum | awk -F= '{print $2}')"
                BZIMAGESHA256="$(grep bzImage-friend chksum | awk '{print $1}')"
                INITRDSHA256="$(grep initrd-friend chksum | awk '{print $1}')"
                [ "$(sha256sum bzImage-friend | awk '{print $1}')" = "$BZIMAGESHA256" ] && [ "$(sha256sum initrd-friend | awk '{print $1}')" = "$INITRDSHA256" ] && cp -f bzImage-friend /mnt/tcrp${chgpart}/ && msgnormal "bzImage OK! \n"
                [ "$(sha256sum bzImage-friend | awk '{print $1}')" = "$BZIMAGESHA256" ] && [ "$(sha256sum initrd-friend | awk '{print $1}')" = "$INITRDSHA256" ] && cp -f initrd-friend /mnt/tcrp${chgpart}/ && msgnormal "initrd-friend OK! \n"
                echo -e "$(msgnormal "$(TEXT "TCRP FRIEND HAS BEEN UPDATED, GOING FOR REBOOT")")"
                countdown "REBOOT"
                reboot -f
            fi
        else
            echo -e "$(msgalert "$(TEXT "No IP yet to check for latest friend")")"
        fi
    fi
}

function upgrademan() {

    if [ -z "$1" ]; then
      echo -en "\r$(msgalert "$(TEXT "There is no TCRP Friend version.!!!")")\n"
      exit 99
    fi

    if [ "${LDTYPE}" = "SHR" ]; then
      chgpart="-p1"
    else
      chgpart="" 
    fi
    
    if [ ! -z "$IP" ]; then

        if [ "${friendautoupd}" = "false" ]; then
            echo -en "\r$(msgwarning "$(TEXT "TCRP Friend auto update disabled")")\n"
        else
            echo -en "\r$(msgwarning "$(TEXT "TCRP Friend auto update enabled")")\n"	
        fi

		FRIENDVERSION="$1"
		msgwarning "Found target version, bringing over new friend version : $FRIENDVERSION \n"

        echo -n $(TEXT "Checking for version $FRIENDVERSION friend -> ")
        URL=$(curl --connect-timeout 15 -s --insecure -L https://api.github.com/repos/PeterSuh-Q3/tcrpfriend/releases/tags/"${FRIENDVERSION}" | jq -r -e .assets[].browser_download_url | grep chksum)
	if [ $? -ne 0 ]; then
	    msgalert "Error downloading version of $FRIENDVERSION friend...\n"
	    exit 99
	fi
	
        # download file chksum
	[ -n "$URL" ] && curl -s --insecure -L $URL -O
	if [ $? -ne 0 ]; then
	    msgalert "Error downloading version of $FRIENDVERSION friend...\n"
	    exit 99
	fi

	URLS=$(curl --insecure -s https://api.github.com/repos/PeterSuh-Q3/tcrpfriend/releases/tags/"${FRIENDVERSION}" | jq -r ".assets[].browser_download_url")
	for file in $URLS; do curl --insecure --location --progress-bar "$file" -O; done
	FRIENDVERSION="$(grep VERSION chksum | awk -F= '{print $2}')"
	BZIMAGESHA256="$(grep bzImage-friend chksum | awk '{print $1}')"
	INITRDSHA256="$(grep initrd-friend chksum | awk '{print $1}')"
	[ "$(sha256sum bzImage-friend | awk '{print $1}')" = "$BZIMAGESHA256" ] && [ "$(sha256sum initrd-friend | awk '{print $1}')" = "$INITRDSHA256" ] && cp -f bzImage-friend /mnt/tcrp${chgpart}/ && msgnormal "bzImage OK! \n"
	[ "$(sha256sum bzImage-friend | awk '{print $1}')" = "$BZIMAGESHA256" ] && [ "$(sha256sum initrd-friend | awk '{print $1}')" = "$INITRDSHA256" ] && cp -f initrd-friend /mnt/tcrp${chgpart}/ && msgnormal "initrd-friend OK! \n"
	echo -e "$(msgnormal "$(TEXT "TCRP FRIEND HAS BEEN UPDATED, GOING FOR REBOOT")")"
 	changeautoupdate "off"
	countdown "REBOOT"
	reboot -f
		
    fi
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

function rebuildloader() {

    losetup -fP /mnt/tcrp/loader72.img
    loopdev=$(losetup -a /mnt/tcrp/loader72.img | awk '{print $1}' | sed -e 's/://')

    if [ -d /root/part1 ]; then
        mount ${loopdev}p1 /root/part1
    else
        mkdir -p /root/part1
        mount ${loopdev}p1 /root/part1
    fi

    if [ -d /root/part2 ]; then
        mount ${loopdev}p2 /root/part2
    else
        mkdir -p /root/part2
        mount ${loopdev}p2 /root/part2
    fi

    localdiskp1="/mnt/tcrp-p1"
    localdiskp2="/mnt/tcrp-p2"

    if [ $(mount | grep -i part1 | wc -l) -eq 1 ] && [ $(mount | grep -i part2 | wc -l) -eq 1 ] && [ $(mount | grep -i ${localdiskp1} | wc -l) -eq 1 ] && [ $(mount | grep -i ${localdiskp2} | wc -l) -eq 1 ]; then
        rm -rf ${localdiskp1}/*
        cp -rf part1/* ${localdiskp1}/
        rm -rf ${localdiskp2}/*
        cp -rf part2/* ${localdiskp2}/
    else
        echo "ERROR: Failed to mount correctly all required partitions"
    fi

    cd /root/

    ####

    umount /root/part1
    umount /root/part2
    losetup -d ${loopdev}
    
}

function checkversionup() {
    revision=$(echo "$version" | cut -d "-" -f2)
    DSM_VERSION=$(cat /mnt/tcrp-p1/GRUB_VER | grep DSM_VERSION | cut -d "=" -f2 | sed 's/"//g')
    if [ ${revision} = '64570' ] && [ ${DSM_VERSION} != '64570' ]; then
        if [ -f /mnt/tcrp/loader72.img ] && [ -f /mnt/tcrp/grub72.cfg ] && [ -f /mnt/tcrp/initrd-dsm72 ]; then
            rebuildloader
            #patchkernel
            #patchramdisk

            echo "copy 7.2 initrd-dsm & grub.cfg"
            cp -vf /mnt/tcrp/grub72.cfg /mnt/tcrp-p1/boot/grub/grub.cfg
            cp -vf /mnt/tcrp/initrd-dsm72 /mnt/tcrp/initrd-dsm
        else
            msgnormal "/mnt/tcrp/loader72.img or /mnt/tcrp/grub72.cfg or /mnt/tcrp/initrd-dsm72 file missing, stop loader full build, please rebuild the loader ..."
            # Check ip upgrade is required
            #checkupgrade
        fi
    else
        msgnormal "Since the revision update was not detected, proceed to the next step. ..."
        # Check ip upgrade is required
        #checkupgrade
    fi
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

function countdown() {
    local timeout=7
    while [ $timeout -ge 0 ]; do
        sleep 1
        printf '\e[35m%s\e[0m\r' "Press <ctrl-c> to stop boot $1 in : $timeout"
        read -t 1 -n 1 key
        case $key in
            'c') # j key
                echo "c key pressed! End script now!"
                exit 99 
                ;;
            'r') # r key
                TEXT "r key pressed! Entering Menu for Reset DSM Password!"
                pip install passlib >/dev/null 2>/dev/null
                sleep 3
                mainmenu
                ;;
            'e') # e key
                TEXT "e key pressed! Entering Menu for Edit USB/SATA Command Line!"
                pip install passlib >/dev/null 2>/dev/null                
                sleep 3
                mainmenu
                ;;
            'j') # j key
                TEXT "j key pressed! Prepare Entering Force Junior (to re-install DSM)!"
                sleep 3
                initialize
                boot forcejunior
                ;;
            *)
                ;;
        esac
        let timeout=$timeout-1
    done
}

function chk_diskcnt() {

  DISKCNT=0

  for edisk in $(fdisk -l | grep "Disk /dev/sd" | awk '{print $2}' | sed 's/://'); do
    if [ $(fdisk -l | grep "83 Linux" | grep ${edisk} | wc -l) -gt 0 ]; then
        continue
    else
        DISKCNT=$((DISKCNT+1))
    fi    
  done

}

function gethw() {

    checkmachine

    echo -ne "Model : $(msgnormal "$model"), Serial : $(msgnormal "$serial"), Mac : $(msgnormal "$mac1"), Build : $(msgnormal "$version"), Update : $(msgnormal "$smallfixnumber"), LKM : $(msgnormal "${redpillmake}")\n"
    echo -ne "Loader BUS: $(msgnormal "${BUS}${SHR_EX_TEXT}")\n"
    THREADS="$(cat /proc/cpuinfo | grep "model name" | awk -F: '{print $2}' | wc -l)"
    CPU="$(cat /proc/cpuinfo | grep "model name" | awk -F: '{print $2}' | uniq)"
    MEM="$(free -h | grep Mem | awk '{print $2}')"
    echo -ne "CPU,MEM: $(msgblue "$CPU") [$(msgnormal "$THREADS") Thread(s)], $(msgblue "$MEM") Memory\n"
    DMI="$(dmesg | grep -i "DMI:" | sed 's/\[.*\] DMI: //i')"
    echo -ne "DMI: $(msgwarning "$DMI")\n"
    HBACNT=$(lspci -nn | egrep -e "\[0104\]" -e "\[0107\]" | wc -l)
    NICCNT=$(lspci -nn | egrep -e "\[0200\]" | wc -l)
    echo -ne "SAS/RAID HBAs Count : $(msgalert "$HBACNT"), NICs Count : $(msgalert "$NICCNT"), SAS/SATA Disks Count : $(msgalert "${DISKCNT}"), NVMe Disks Count : $(msgalert "${NVMECNT}")\n"
    [ -d /sys/firmware/efi ] && msgnormal "System is running in UEFI boot mode\n" && EFIMODE="yes" || msgblue "System is running in Legacy boot mode\n"    
}

function checkmachine() {

    if grep -q ^flags.*\ hypervisor\  /proc/cpuinfo; then
        MACHINE="VIRTUAL"
        HYPERVISOR=$(lscpu | grep "Hypervisor vendor" | awk '{print $3}')
        echo "Machine is $MACHINE and the Hypervisor is $HYPERVISOR"
    else
        MACHINE="BAREMETAL"    
    fi

}

###############################################################################
# get bus of disk
# 1 - device path
function getBus() {
  local bus=""
  local device_path="$1"
  # usb/ata(sata/ide)/scsi
  [ -z "${bus}" ] && bus=$(udevadm info --query property --name "${device_path}" 2>/dev/null | grep ID_BUS | cut -d= -f2 | sed 's/ata/sata/')
  # usb/sata(sata/ide)/nvme
  [ -z "${bus}" ] && bus=$(lsblk -dpno KNAME,TRAN 2>/dev/null | grep "${device_path} " | awk '{print $2}') #Spaces are intentional
  # usb/scsi(sata/ide)/virtio(scsi/virtio)/mmc/nvme
  [ -z "${bus}" ] && bus=$(lsblk -dpno KNAME,SUBSYSTEMS 2>/dev/null | grep "${device_path} " | awk -F':' '{print $(NF-1)}' | sed 's/_host//') #Spaces are intentional
  echo "${bus}"
}

function getusb() {

    # Get the VID/PID if we are in USB
    VID="0x0000"
    PID="0x0000"
    
    if [ "${BUS}" = "usb" ]; then
        VID="0x$(udevadm info --query property --name ${LOADER_DISK} | grep ID_VENDOR_ID | cut -d= -f2)"
        PID="0x$(udevadm info --query property --name ${LOADER_DISK} | grep ID_MODEL_ID | cut -d= -f2)"
        updateuserconfigfield "extra_cmdline" "pid" "$PID"
        updateuserconfigfield "extra_cmdline" "vid" "$VID"
        curpid=$(jq -r -e .general.usb_line $userconfigfile | awk -Fpid= '{print $2}' | awk '{print  $1}')
        curvid=$(jq -r -e .general.usb_line $userconfigfile | awk -Fvid= '{print $2}' | awk '{print  $1}')
        sed -i "s/${curpid}/${PID}/" $userconfigfile
        sed -i "s/${curvid}/${VID}/" $userconfigfile
    fi

}

function matchpciidmodule() {

    vendor="$(echo $1 | tr 'a-z' 'A-Z')"
    device="$(echo $2 | tr 'a-z' 'A-Z')"

    pciid="${vendor}d0000${device}"

    # Correction to work with tinycore jq
    matchedmodule=$(jq -e -r ".modules[] | select(.alias | contains(\"${pciid}\")?) | .name " $MODULE_ALIAS_FILE)

    # Call listextensions for extention matching
    echo "$matchedmodule"

}

function sortnetif() {
  ETHLIST=""
  ETHX=$(ls /sys/class/net/ 2>/dev/null | grep eth) # real network cards list
  for ETH in ${ETHX}; do
    MAC="$(cat /sys/class/net/${ETH}/address 2>/dev/null | sed 's/://g' | tr '[:upper:]' '[:lower:]')"
    BUSINFO=$(ethtool -i ${ETH} 2>/dev/null | grep bus-info | awk '{print $2}')
    ETHLIST="${ETHLIST}${BUSINFO} ${MAC} ${ETH}\n"
  done
  
  ETHLIST="$(echo -e "${ETHLIST}" | sort)"
  ETHLIST="$(echo -e "${ETHLIST}" | grep -v '^$')"
  
  echo -e "${ETHLIST}" >/tmp/ethlist
  cat /tmp/ethlist
  
  # sort
  IDX=0
  while true; do
    cat /tmp/ethlist
    [ ${IDX} -ge $(wc -l </tmp/ethlist) ] && break
    ETH=$(cat /tmp/ethlist | sed -n "$((${IDX} + 1))p" | awk '{print $3}')
    echo "ETH: ${ETH}"
    if [ -n "${ETH}" ] && [ ! "${ETH}" = "eth${IDX}" ]; then
        echo "change ${ETH} <=> eth${IDX}"
        ip link set dev eth${IDX} down
        ip link set dev ${ETH} down
        sleep 1
        ip link set dev eth${IDX} name tmp
        ip link set dev ${ETH} name eth${IDX}
        ip link set dev tmp name ${ETH}
        sleep 1
        ip link set dev eth${IDX} up
        ip link set dev ${ETH} up
        sleep 1
        sed -i "s/eth${IDX}/tmp/" /tmp/ethlist
        sed -i "s/${ETH}/eth${IDX}/" /tmp/ethlist
        sed -i "s/tmp/${ETH}/" /tmp/ethlist
        sleep 1
    fi
    IDX=$((${IDX} + 1))
  done
  
  rm -f /tmp/ethlist
  sleep 2
}

function getip() {

    ethdevs=$(ls /sys/class/net/ | grep -v lo || true)

    sleep 3
    # Wait for an IP
    for eth in $ethdevs; do 
        COUNT=0
        DRIVER=$(ls -ld /sys/class/net/${eth}/device/driver 2>/dev/null | awk -F '/' '{print $NF}')
        if [ $(ls -l /sys/class/net/${eth}/device | grep "0000:" | wc -l) -gt 0 ]; then
            BUSID=$(ls -ld /sys/class/net/${eth}/device 2>/dev/null | awk -F '0000:' '{print $NF}')
        else
            BUSID=""
        fi
        if [ -f /sys/class/net/${eth}/device/vendor ] && [ -f /sys/class/net/${eth}/device/device ]; then        
            VENDOR=$(cat /sys/class/net/${eth}/device/vendor | sed 's/0x//')
            DEVICE=$(cat /sys/class/net/${eth}/device/device | sed 's/0x//')
            if [ ! -z "${VENDOR}" ] && [ ! -z "${DEVICE}" ]; then
                MATCHDRIVER=$(echo "$(matchpciidmodule ${VENDOR} ${DEVICE})")
                if [ ! -z "${MATCHDRIVER}" ]; then
                    if [ "${MATCHDRIVER}" != "${DRIVER}" ]; then
                        DRIVER=${MATCHDRIVER}
                    fi
                fi
            fi
        fi    
        while true; do
            if [ ${COUNT} -eq 5 ]; then
                break
            fi
            COUNT=$((${COUNT} + 1))
            if [ $(ip route | grep default | grep metric | grep ${eth} | wc -l) -eq 1 ]; then
                IP="$(ip route show dev ${eth} 2>/dev/null | grep default | grep metric | awk '{print $7}')"
                #IP="$(ip route get 1.1.1.1 2>/dev/null | grep ${eth} | awk '{print $7}')"
                IP=$(echo -n "${IP}" | tr '\n' '\b')
                LASTIP="${IP}"
                break
            else
                IP=""
            fi
            sleep 1
        done
        [ -n "${IP}" ] && echo "IP Addr : $(msgnormal "${IP}"), Network Interface Card : ${BUSID}, ${eth} [${VENDOR}:${DEVICE}] (${DRIVER}) "
    done
    IP="${LASTIP}"
}

function checkfiles() {

    files="user_config.json initrd-dsm zImage-dsm"

    for file in $files; do
        if [ -f /mnt/tcrp/$file ]; then
            msgnormal "File : $file OK !"
        else
            msgnormal "File : $file missing  !"
            exit 99
        fi

    done

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

function setmac() {

    # Set custom MAC if defined
    ethdevs=$(ls /sys/class/net/ | grep -v lo || true)
    /etc/init.d/S41dhcpcd stop >/dev/null 2>&1
    /etc/init.d/S40network stop >/dev/null 2>&1    
    I=1
    for eth in $ethdevs; do 
        curmacmask=$(ip link | grep -A 1 ${eth} | tail -1 | awk '{print $2}' | tr '[:lower:]' '[:upper:]')
        eval "usrmac=\${mac${I}}"
        MAC="${usrmac:0:2}:${usrmac:2:2}:${usrmac:4:2}:${usrmac:6:2}:${usrmac:8:2}:${usrmac:10:2}"
        DRIVER=$(ls -ld /sys/class/net/${eth}/device/driver 2>/dev/null | awk -F '/' '{print $NF}')
        if [ "${usrmac}" != "null" ]; then
            msgnormal "Setting MAC Address from ${curmacmask} to ${MAC} on ${eth} (${DRIVER})\n" | tee -a boot.log
            ip link set dev ${eth} address ${MAC} >/dev/null 2>&1 
        fi
        I=$((${I} + 1))
        if [ "${eth}" = "eth8" ]; then
            break
        fi
    done
    /etc/init.d/S40network start >/dev/null 2>&1
    /etc/init.d/S41dhcpcd start >/dev/null 2>&1    

}

function setnetwork() {

    ethdev=$(ip a | grep UP | grep -v LOOP | head -1 | awk '{print $2}' | sed -e 's/://g')

    echo "Network settings are set to static proceeding setting static IP settings" | tee -a boot.log
    staticip="$(jq -r -e .ipsettings.ipaddr /mnt/tcrp/user_config.json)"
    staticdns="$(jq -r -e .ipsettings.ipdns /mnt/tcrp/user_config.json)"
    staticgw="$(jq -r -e .ipsettings.ipgw /mnt/tcrp/user_config.json)"
    staticproxy="$(jq -r -e .ipsettings.ipproxy /mnt/tcrp/user_config.json)"

    [ -n "$staticip" ] && [ $(ip a | grep $staticip | wc -l) -eq 0 ] && ip a add "$staticip" dev $ethdev | tee -a boot.log
    [ -n "$staticdns" ] && [ $(grep ${staticdns} /etc/resolv.conf | wc -l) -eq 0 ] && sed -i "a nameserver $staticdns" /etc/resolv.conf | tee -a boot.log
    [ -n "$staticgw" ] && [ $(ip route | grep "default via ${staticgw}" | wc -l) -eq 0 ] && ip route add default via $staticgw dev $ethdev | tee -a boot.log
    [ -n "$staticproxy" ] &&
        export HTTP_PROXY="$staticproxy" && export HTTPS_PROXY="$staticproxy" &&
        export http_proxy="$staticproxy" && export https_proxy="$staticproxy" | tee -a boot.log

    IP="$(ip route get 1.1.1.1 2>/dev/null | grep $ethdev | awk '{print $7}')"
    if [ -n "${IP}" ]; then
        DRIVER=$(ls -ld /sys/class/net/${ethdev}/device/driver 2>/dev/null | awk -F '/' '{print $NF}')
        VENDOR=$(cat /sys/class/net/${ethdev}/device/vendor | sed 's/0x//')
        DEVICE=$(cat /sys/class/net/${ethdev}/device/device | sed 's/0x//')
        if [ ! -z "${VENDOR}" ] && [ ! -z "${DEVICE}" ]; then
            MATCHDRIVER=$(echo "$(matchpciidmodule ${VENDOR} ${DEVICE})")
            if [ ! -z "${MATCHDRIVER}" ]; then
                if [ "${MATCHDRIVER}" != "${DRIVER}" ]; then
                    DRIVER=${MATCHDRIVER}
                fi
            fi
        fi    
        echo "IP Address : $(msgnormal "${IP}"), Network Interface Card : ${ethdev} [${VENDOR}:${DEVICE}] (${DRIVER}) "    
    fi
}

function wait_mmc() {
    EMMCBOOT='false'
    for i in {1..10}; do
        sleep 1
        if lsblk | grep -q mmcblk && lsblk -nro UUID | grep -q '6234-C863'; then
            echo "mmc device detected after $i second(s)."
            EMMCBOOT='true'
            return 0
        fi
        echo "mmc device detecting in $i second(s)."
    done
    echo "mmc device not detected after waiting."
}

function getloadertype() {
    
    # Get the list of loader partition's UUIDs
    uuids=$(lsblk -nro UUID | awk 'length($0)==9')
    
    # Group UUIDs by disk
    declare -A disk_uuids
    while IFS= read -r uuid; do
        # Process only if UUID is not empty and matches the valid format
        if [[ -n "$uuid" ]]; then
            disk=$(lsblk -nro PKNAME,UUID | grep "$uuid" | awk '{print $1}')
            if [[ -n "$disk" ]]; then
                disk_uuids["$disk"]+="$uuid "
            fi
        fi
    done <<< "$uuids"
    
    # Print the results
    for disk in "${!disk_uuids[@]}"; do
        echo "Disk: $disk, UUIDs: ${disk_uuids[$disk]}"
    done
    
    # Search for UUIDs and set LDTYPE
    uuid1="1234-5678"
    uuid2="8765-4321"
    uuid3="6234-C863"
    LDTYPE=""
    LOADER_DISK=""
    
    # Search for uuid3 first
    for disk in "${!disk_uuids[@]}"; do
        if [[ "${disk_uuids[$disk]}" == *"$uuid3"* ]]; then
            LDTYPE="NORMAL"
            LOADER_DISK=${disk#/dev/}
            #echo "LDTYPE=$LDTYPE"
            #echo "LOADER_DISK=$LOADER_DISK"
            return
        fi
    done
    
    # If uuid3 is not found, search for uuid1 and uuid2
    found_uuid1=false
    found_uuid2=false
    
    for disk in "${!disk_uuids[@]}"; do
        if [[ "${disk_uuids[$disk]}" == *"$uuid1"* ]]; then
            found_uuid1=true
        fi
        if [[ "${disk_uuids[$disk]}" == *"$uuid2"* ]]; then
            found_uuid2=true
            LOADER_DISK=${disk#/dev/}
        fi
    done
    
    if $found_uuid1 && $found_uuid2; then
        LDTYPE="SHR"
        #echo "LDTYPE=$LDTYPE"
        #echo "LOADER_DISK=$LOADER_DISK"
	    return
    else 
        echo "No Redpill loader partitions found. Exiting!!!"
	    echo "Wait for additional time until mmc device is recognized..."
	    wait_mmc
 	    getloadertype
        [ "${EMMCBOOT}" = "true" ] && return || exit 99
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

function mountxtcrp() {

    [ ! -d /mnt/${LOADER_DISK}1 ] && mkdir /mnt/${LOADER_DISK}1
    [ ! -d /mnt/${LOADER_DISK}2 ] && mkdir /mnt/${LOADER_DISK}2
    [ ! -d /mnt/${LOADER_DISK}3 ] && mkdir /mnt/${LOADER_DISK}3

    [ "$(mount | grep /mnt/${LOADER_DISK}1 | wc -l)" = "0" ] && mount /dev/${LOADER_DISK}${p1} /mnt/${LOADER_DISK}1
    [ "$(mount | grep /mnt/${LOADER_DISK}2 | wc -l)" = "0" ] && mount /dev/${LOADER_DISK}${p2} /mnt/${LOADER_DISK}2
    [ "$(mount | grep /mnt/${LOADER_DISK}3 | wc -l)" = "0" ] && mount /dev/${LOADER_DISK}${p3} /mnt/${LOADER_DISK}3

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

function boot() {

    # Welcome message
    welcome

    gethw

    #Compare with the number of pre-counted disks in tcrp 0.1.1i
    if [ "${chkdisk}" = "true" ]; then
        if [ "${usrdisks}" != "${DISKCNT}" ]; then
            msgalert "It is different from the number of disks pre-counted (${usrdisks}) in tcrp!!!\n"
            msgalert "To protect partitions within DSM,A shutdown is required. Press any key to shutdown..."
            read answer
            poweroff
        fi
    fi

    # user_config.json ipsettings block

    #  "ipsettings" : {
    #     "ipset": "static",
    #     "ipaddr":"192.168.71.146/24",
    #     "ipgw" : "192.168.71.1",
    #     "ipdns": "",
    #     "ipproxy" : ""
    # },
    if [ "$(jq -r -e .ipsettings.ipset /mnt/tcrp/user_config.json)" = "static" ]; then
        setnetwork
    else
        sortnetif 2>&1 | awk '{ print strftime("%Y-%m-%d %H:%M:%S"), $0; }' >>$FRIENDLOG
        # Set Mac Address according to user_config
        setmac

        # Get IP Address after setting new mac address to display IP
        getip
    fi

    # Check whether the major version has been updated from under 7.2 to 7.2
    #checkversionup

    [ -z "$IP" ] && getip

    # Check ip upgrade is required
    checkupgrade

    # Get USB list and set VID-PID Automatically
    getusb

    # check if new TCRP Friend version is available to download
    [ -z "$IP" ] && getip
    checkinternet

    [ "${INTERNET}" = "ON" ] && upgradefriend

    if [ -f /mnt/tcrp/stopatfriend ]; then
        echo "Stop at friend detected, stopping boot"
        rm -f /mnt/tcrp/stopatfriend
        touch /root/stoppedatrequest
        exit 0
    fi

    if grep -q "debugfriend" /proc/cmdline; then
        echo "Debug Friend set, stopping boot process"
        exit 0
    fi

    if [ "${BUS}" = "sata" ]; then
        CMDLINE_LINE=$(jq -r -e '.general .sata_line' /mnt/tcrp/user_config.json)
        # Check dom size and set max size accordingly
        # 2024.03.17 Force the dom_szmax limit of the injected bootloader to be 16GB
        CMDLINE_LINE+="dom_szmax=$(fdisk -l /dev/${LOADER_DISK} | head -1 | awk -F: '{print $2}' | awk '{ print $1*1024}') "
    	if [ "${LDTYPE}" = "SHR" ]; then
            CMDLINE_LINE=$(echo "$CMDLINE_LINE" | sed -E 's/synoboot_satadom=[12]\s*//g')
  	fi
    else
        CMDLINE_LINE=$(jq -r -e '.general .usb_line' /mnt/tcrp/user_config.json)
    fi

    #[ "$1" = "gettycon" ] && CMDLINE_LINE+=" gettycon "

    [ "$1" = "forcejunior" ] && CMDLINE_LINE+="force_junior "

    #CMDLINE_LINE+="skip_vender_mac_interfaces=0,1,2,3,4,5,6,7 "

    #If EFI then add withefi to CMDLINE_LINE
    if [ "$EFIMODE" = "yes" ] && [ $(echo ${CMDLINE_LINE} | grep withefi | wc -l) -le 0 ]; then
        CMDLINE_LINE+="withefi " && echo -en "\r$(msgwarning "$(TEXT "EFI booted system with no EFI option, adding withefi to cmdline")")\n"
    fi

    if [ "$(dmidecode -s system-manufacturer | grep -c VMware)" -eq 1 ]; then
        CMDLINE_LINE+="mev=vmware "
    elif [ "$(dmidecode -s system-manufacturer | grep -c QEMU)" -eq 1 ]; then
        CMDLINE_LINE+="mev=qemu "
    fi

    export MOD_ZIMAGE_FILE="/mnt/tcrp/zImage-dsm"
    export MOD_RDGZ_FILE="/mnt/tcrp/initrd-dsm"

    echo -e "$(msgcyan "$(TEXT "User config is on '/mnt/tcrp/user_config.json'")")"
    echo
    echo "zImage : ${MOD_ZIMAGE_FILE} initrd : ${MOD_RDGZ_FILE}, Module Processing Method : $(msgnormal "${dmpm}")"
    echo "cmdline : $(msgblue "${CMDLINE_LINE}")"
    echo
    echo -en "$(msgpurple "$(TEXT "To check the problem, access the following TTYD URL through a web browser. :")")"
    echo " http://${IP}:7681"
    echo -e "$(msgalert "$(TEXT "Default TTYD root password is 'blank' ")")"    
    echo -e "$(msgwarning "$(TEXT "If you have any problems with the DSM installation steps, check the '/var/log/linuxrc.syno.log' file in this access.")")"
    echo            
    #if [ "$1" != "gettycon" ] && [ "$1" != "forcejunior" ]; then    
    if [ "$1" != "forcejunior" ]; then    
 #       msgalert "Press <g> to enter a Getty Console to solve trouble\n"
        echo -e "$(msgalert "$(TEXT "Press <r> to enter a menu for Reset DSM Password")")"
        echo -e "$(msgnormal "$(TEXT "Press <e> to enter a menu for Edit USB/SATA Command Line")")"
        echo -e "$(msgwarning "$(TEXT "Press <j> to enter a Junior mode (to re-install DSM)")")"
#    elif [ "$1" = "gettycon" ]; then
#        msgalert "Entering a Getty Console to solve trouble...\n"
    elif [ "$1" = "forcejunior" ]; then
        echo -e "$(msgwarning "$(TEXT "Entering a Junior mode (to re-install DSM)...")")"
    fi
    
    # Check netif_num matches the number of configured mac addresses as if these does not match redpill will cause a KP
    echo ${CMDLINE_LINE} >/tmp/cmdline.out
    while IFS=" " read -r -a line; do
        printf "%s\n" "${line[@]}"
    done </tmp/cmdline.out | egrep -i "sn|pid|vid|mac|hddhotplug|netif_num" | sort >/tmp/cmdline.check

    [ $(grep sn /tmp/cmdline.check | wc -l) -eq 0 ] && msgalert "FAILED to find sn in CMDLINE, DSM will panic, exiting so you can fix this\n" && exit 99
    [ $(grep netif_num /tmp/cmdline.check | wc -l) -eq 0 ] && msgalert "FAILED to find netif_num in CMDLINE, DSM will panic, exiting so you can fix this\n" && exit 99
    [ $(grep mac /tmp/cmdline.check | wc -l) -eq 0 ] && msgalert "FAILED to find mac# in CMDLINE, DSM will panic, exiting so you can fix this\n" && exit 99
    . /tmp/cmdline.check
    [ $(grep mac /tmp/cmdline.check | grep -v vender_mac | wc -l) != $netif_num ] && msgalert "FAILED to match the count of configured netif_num and mac addresses, DSM will panic, exiting so you can fix this\n" && exit 99

    if [ "$staticboot" = "true" ]; then
        TEXT "Static boot set, rebooting to static ..."
        cp tools/libdevmapper.so.1.02 /usr/lib
        cp tools/grub-editenv /usr/bin
        chmod +x /usr/bin/grub-editenv
        /usr/bin/grub-editenv /mnt/tcrp-p1/boot/grub/grubenv create        
        [ "${BUS}" = "sata" ] && setgrubdefault 1
        [ "${BUS}" = "usb" ] && setgrubdefault 0
        reboot
    else

        #if [ "$1" != "gettycon" ] && [ "$1" != "forcejunior" ]; then
        if [ "$1" != "forcejunior" ]; then
            countdown "booting"
        fi
        echo -en "\r$(TEXT "Boot timeout exceeded, booting ... ")\n"
        echo
        echo -en "\r$(TEXT "\"HTTP, Synology Web Assistant (BusyBox httpd)\" service may take 20 - 40 seconds.")\n"
        echo -en "\r$(TEXT "(Network access is not immediately available)")\n"
        echo -en "\r$(TEXT "Kernel loading has started, nothing will be displayed here anymore ...")\n"
        echo -en "$(msgnormal "$(TEXT "Enter the following address in your web browser :")")"
        echo " http://${IP}:5000"        

		[ -n "${IP}" ] && URL="http://${IP}:5000" || URL="https://finds.synology.com/"
		python3 /root/functions.py makeqr -d "${URL}" -l "7" -o "/tmp/qrcode.png"
		[ -f "/tmp/qrcode.png" ] && echo | fbv -acufi "/tmp/qrcode.png" >/dev/null 2>&1 || true
        
        [ "${hidesensitive}" = "true" ] && clear

        if [ $(echo ${CMDLINE_LINE} | grep withefi | wc -l) -eq 1 ]; then
            kexec -l "${MOD_ZIMAGE_FILE}" --initrd "${MOD_RDGZ_FILE}" --command-line="${CMDLINE_LINE}"
        else
            echo -e "$(msgwarning "$(TEXT "Booting with noefi, please notice that this might cause issues")")"
            kexec --noefi -l "${MOD_ZIMAGE_FILE}" --initrd "${MOD_RDGZ_FILE}" --command-line="${CMDLINE_LINE}"
        fi

        kexec -f -e
    fi
}

function welcome() {

    clear
    echo -en "\033[7;32m--------------------------------------={ TinyCore RedPill Friend }=--------------------------------------\033[0m\n"

    # Echo Version
    echo "TCRP Friend Version : $BOOTVER"
    showlastupdate
}

function chk_diskcnt() {
  DISKCNT=0
  while read -r edisk; do
    if [ $(/sbin/fdisk -l "$edisk" | grep -c "83 Linux") -eq 3 ]; then
        continue
    else
        DISKCNT=$((DISKCNT+1))
    fi    
  done < <(lsblk -ndo NAME | grep '^sd' | sed 's/^/\/dev\//')
}

function chk_nvmecnt() {
  NVMECNT=0
  while read -r edisk; do
    if [ $(/sbin/fdisk -l "$edisk" | grep -c "83 Linux") -eq 3 ]; then
        continue
    else
        NVMECNT=$((NVMECNT+1))
    fi    
  done < <(lsblk -ndo NAME | grep '^nvme' | sed 's/^/\/dev\//')
}

function initialize() {
    # Checkif running in TC
    [ "$(hostname)" != "tcrpfriend" ] && echo "ERROR running on alien system" && exit 99

    # check disk count
    chk_diskcnt
    # check nvme count
    chk_nvmecnt
    # Mount loader disk
    [ -z "${LOADER_DISK}" ] && mountall

    if [ -z "$1" ]; then 
        if grep -q "IWANTTOCONFIGURE" /proc/cmdline; then
            echo "Proceed with configuring the selected loader..."
            tar -xzvf /mnt/tcrp/xtcrp.tgz -C /home/tc 2>&1 >/dev/null
    	    chown -R tc:tc /home/tc
	 
	    touch /etc/init.d/tc-functions
            mkdir -p /etc/sysconfig
	    touch /etc/sysconfig/tcuser
	    [ ! -f /usr/bin/menu.sh ] && ln -s /home/tc/menu.sh /usr/bin/menu.sh
            [ ! -f /usr/bin/monitor.sh ] && ln -s /home/tc/monitor.sh /usr/bin/monitor.sh
            [ ! -f /usr/bin/ntp.sh ] && ln -s /home/tc/ntp.sh /usr/bin/ntp.sh

            [ ! -d /mnt/tcrp/auxfiles ] && mkdir -p /mnt/tcrp/auxfiles
    	    echo "export PATH=$PATH:/sbin" >> /home/tc/.profile
    	    mountxtcrp
            echo -e "Configure the loader using the \e[32mmenu.sh\e[0m command." 
	    echo -e "To check system information and boot entries using the \e[33mmonitor.sh\e[0m command." 
            echo -e "To check the settings and installed addons using the \e[35mntp.sh\e[0m command." 
            echo ""
	    sleep 3
            IP="$(ip route show dev eth0 2>/dev/null | grep default | grep metric | awk '{print $7}')"
            IP=$(echo -n "${IP}" | tr '\n' '\b')
            echo -e "To use the xTCRP web console, access \e[33m${IP}:7681\e[0m with a web browser."
            su - tc
            exit 0
        fi
    fi
    # Read Configuration variables
    readconfig

    # No network devices
    eths=$(ls /sys/class/net/ | grep -v lo || true)    
    [ $(echo ${eths} | wc -w) -le 0 ] && TEXT "No NIC found! - Loader does not work without Network connection." && exit 99

    # Update user config file to latest version
    updateuserconfigfile

    [ "${smallfixnumber}" = "null" ] && patchramdisk 2>&1 | awk '{ print strftime("%Y-%m-%d %H:%M:%S"), $0; }' >>$FRIENDLOG

    # unzip modules.alias
    [ -f modules.alias.3.json.gz ] && gunzip -f modules.alias.3.json.gz
    [ -f modules.alias.4.json.gz ] && gunzip -f modules.alias.4.json.gz    

    ORIGIN_PLATFORM=$(cat /mnt/tcrp-p1/GRUB_VER | grep PLATFORM | cut -d "=" -f2 | tr '[:upper:]' '[:lower:]' | sed 's/"//g')

    case $ORIGIN_PLATFORM in
    avoton | bromolow | braswell | cedarview | grantley)
        MODULE_ALIAS_FILE="modules.alias.3.json"
        ;;
    apollolake | broadwell | broadwellnk | v1000 | denverton | geminilake | broadwellnkv2 | broadwellntbap | purley | *)
        MODULE_ALIAS_FILE="modules.alias.4.json"
        ;;
    esac
}

case $1 in

updateauto)
    initialize
    getip
    upgradefriend
    ;;

update)
    initialize "normal"
    getip
    upgrademan "$2"
    ;;

autoupdate)
    initialize
    changeautoupdate "$2"
    ;;

checkupgrade)
    initialize
    checkupgrade
    ;;

patchramdisk)
    initialize
    patchramdisk
    ;;

patchkernel)
    initialize
    patchkernel
    ;;

rebuildloader)
    initialize
    rebuildloader
    cp -vf /mnt/tcrp/grub72.cfg /mnt/tcrp-p1/boot/grub/grub.cfg
    cp -vf /mnt/tcrp/initrd-dsm72 /mnt/tcrp/initrd-dsm    
    #patchkernel
    #patchramdisk
    ;;

version)
    version $@
    ;;

extractramdisk)
    initialize
    extractramdisk
    ;;

forcejunior)
    initialize
    boot "forcejunior"
    ;;

#gettycon)
#    initialize
#    boot gettycon
#    ;;

menu)
    mainmenu
    initialize
    boot
    ;;
normal)    
    initialize "normal"
    boot
    ;;
*)
    initialize
    # All done, lets go for boot/
    boot
    ;;

esac
