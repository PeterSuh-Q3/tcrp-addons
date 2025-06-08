#!/bin/sh

set -o pipefail 

PLATFORM="$(uname -a | awk '{print $NF}' | cut -d '_' -f2)"

SED_PATH='/tmpRoot/usr/bin/sed'
XXD_PATH='/tmpRoot/usr/bin/xxd'
LSPCI_PATH='/tmpRoot/usr/bin/lspci'

fixcpufreq() {

    if [ $(mount 2>/dev/null | grep sysfs | wc -l) -eq 0 ]; then
        mount -t sysfs sysfs /sys
        [ -f /tmpRoot/usr/lib/modules/processor.ko ] && insmod /tmpRoot/usr/lib/modules/processor.ko
        [ -f /tmpRoot/usr/lib/modules/acpi-cpufreq.ko ] && insmod /tmpRoot/usr/lib/modules/acpi-cpufreq.ko
    fi
    # CPU performance scaling
    if [ -f /tmpRoot/usr/lib/modules-load.d/70-cpufreq-kernel.conf ]; then
        cpufreq=$(ls -ltr /sys/devices/system/cpu/cpufreq/* 2>/dev/null | wc -l)
        if [ $cpufreq -eq 0 ]; then
            echo "CPU does NOT support CPU Performance Scaling, disabling"
            ${SED_PATH} -i 's/^acpi-cpufreq/# acpi-cpufreq/g' /tmpRoot/usr/lib/modules-load.d/70-cpufreq-kernel.conf
        else
            echo "CPU supports CPU Performance Scaling, enabling"
            ${SED_PATH} -i 's/^# acpi-cpufreq/acpi-cpufreq/g' /tmpRoot/usr/lib/modules-load.d/70-cpufreq-kernel.conf
        fi
    fi
    umount /sys
}

fixcrypto() {
    # crc32c-intel
    if [ -f /tmpRoot/usr/lib/modules-load.d/70-crypto-kernel.conf ]; then
        CPUFLAGS=$(cat /proc/cpuinfo | grep flags | grep sse4_2 | wc -l)
        if [ $CPUFLAGS -gt 0 ]; then
            echo "CPU Supports SSE4.2, crc32c-intel should load"
        else
            echo "CPU does NOT support SSE4.2, crc32c-intel will not load, disabling"
            ${SED_PATH} -i 's/^crc32c-intel/# crc32c-intel/g' /tmpRoot/usr/lib/modules-load.d/70-crypto-kernel.conf
        fi
    fi

    # aesni-intel
    if [ -f /tmpRoot/usr/lib/modules-load.d/70-crypto-kernel.conf ]; then
        CPUFLAGS=$(cat /proc/cpuinfo | grep flags | grep aes | wc -l)
        if [ ${CPUFLAGS} -gt 0 ]; then
            echo "CPU Supports AES, aesni-intel should load"
        else
            echo "CPU does NOT support AES, aesni-intel will not load, disabling"
            ${SED_PATH} -i 's/support_aesni_intel="yes"/support_aesni_intel="no"/' /tmpRoot/etc.defaults/synoinfo.conf
            ${SED_PATH} -i 's/^aesni-intel/# aesni-intel/g' /tmpRoot/usr/lib/modules-load.d/70-crypto-kernel.conf
        fi
    fi
}

fixnvidia() {
    # Nvidia GPU
    if [ -f /tmpRoot/usr/lib/modules-load.d/70-syno-nvidia-gpu.conf ]; then
        NVIDIADEV=$(cat /proc/bus/pci/devices 2>/dev/null | grep -i 10de | wc -l)
        if [ $NVIDIADEV -eq 0 ]; then
            echo "NVIDIA GPU is not detected, disabling "
            ${SED_PATH} -i 's/^nvidia/# nvidia/g' /tmpRoot/usr/lib/modules-load.d/70-syno-nvidia-gpu.conf
            ${SED_PATH} -i 's/^nvidia-uvm/# nvidia-uvm/g' /tmpRoot/usr/lib/modules-load.d/70-syno-nvidia-gpu.conf
        else
            echo "NVIDIA GPU is detected, nothing to do"
        fi
    fi
}

fixintelgpu() {
  # Intel GPU
  echo "replace intel gpu info for i915le10th"

  GPU="$(lspci -nd ::300 2>/dev/null | grep 8086 | cut -d' ' -f3 | sed 's/://g')"
  grep -iq "${GPU}" "/usr/sbin/i915ids" 2>/dev/null || GPU=""
  if [ -z "${GPU}" ] || [ $(echo -n "${GPU}" | wc -c) -ne 8 ]; then
    echo "GPU is not detected"
    exit 0
  fi

  KO_FILE="/usr/lib/modules/i915.ko"
  if [ ! -f "${KO_FILE}" ]; then
    echo "i915.ko does not exist"
    exit 0
  fi  

  isLoad=0
  if lsmod 2>/dev/null | grep -q "^i915"; then
    isLoad=1
    echo "removing i915 ..." 
    /usr/sbin/modprobe -r i915
  fi
  GPU_DEF="86800000923e0000"
  GPU_BIN="${GPU:2:2}${GPU:0:2}0000${GPU:6:2}${GPU:4:2}0000"
  echo "GPU:${GPU} GPU_BIN:${GPU_BIN}"
  cp -pf "${KO_FILE}" "${KO_FILE}.tmp"
  if xxd -c $(xxd -p "${KO_FILE}.tmp" 2>/dev/null | wc -c) -p "${KO_FILE}.tmp" 2>/dev/null |
    sed "s/${GPU_DEF}/${GPU_BIN}/; s/308201f706092a86.*70656e6465647e0a//" |
    xxd -r -p >"${KO_FILE}" 2>/dev/null; then
    echo "i915 xxd proc success!!!" 
  else  
    echo "i915 xxd proc fail!!!" 
  fi  
  rm -vf "${KO_FILE}.tmp"
  #if [ "${isLoad}" = "1" ]; then
  #  echo "doing modprobe i915 ..." 
  #  /usr/sbin/modprobe i915
  #fi
  
}

copyintelgpu() {
  KO_FILE="/tmpRoot/usr/lib/modules/i915.ko"
  [ ! -f "${KO_FILE}.bak" ] && cp -vf "${KO_FILE}" "${KO_FILE}.bak"
  cp -vf "/usr/lib/modules/i915.ko" "${KO_FILE}"
}

fixacpibutton() {
    #button.ko

    if [ ! -d /proc/acpi ]; then
        echo "NO ACPI status is available, disabling button.ko"
        ${SED_PATH} -i 's/^button/# button/g' /tmpRoot/usr/lib/modules-load.d/70-video-kernel.conf
    fi

}

fixservice() {
  # service
  # systemd-modules-load SynoInitEth syno-oob-check-status syno_update_disk_logs
  rm -vf /tmpRoot/usr/lib/modules-load.d/70-network*.conf
  SERVICE_PATH="/tmpRoot/usr/lib/systemd/system"
  ${SED_PATH} -i 's|ExecStart=/|ExecStart=-/|g' ${SERVICE_PATH}/systemd-modules-load.service
  ${SED_PATH} -i 's|ExecStart=/|ExecStart=-/|g' ${SERVICE_PATH}/syno-oob-check-status.service 
  ${SED_PATH} -i 's|ExecStart=/|ExecStart=-/|g' ${SERVICE_PATH}/SynoInitEth.service 
  ${SED_PATH} -i 's|ExecStart=/|ExecStart=-/|g' ${SERVICE_PATH}/syno_update_disk_logs.service
}

fixsdcard() {
  # sdcard
  [ ! -f /tmpRoot/usr/lib/udev/script/sdcard.sh.bak ] && cp -vpf /tmpRoot/usr/lib/udev/script/sdcard.sh /tmpRoot/usr/lib/udev/script/sdcard.sh.bak
  printf '#!/bin/sh\nexit 0\n' >/tmpRoot/usr/lib/udev/script/sdcard.sh
}

fixnetwork() {
  # network
  if grep -q 'network.' /proc/cmdline; then
    for I in $(grep -Eo 'network.[0-9a-fA-F:]{12,17}=[^ ]*' /proc/cmdline); do
      MACR="$(echo "${I}" | cut -d. -f2 | cut -d= -f1 | sed 's/://g; s/.*/\L&/')"
      IPRS="$(echo "${I}" | cut -d= -f2)"
      for F in /sys/class/net/eth*; do
        [ ! -e "${F}" ] && continue
        ETH="$(basename "${F}")"
        MACX=$(cat "/sys/class/net/${ETH}/address" 2>/dev/null | sed 's/://g; s/.*/\L&/')
        if [ "${MACR}" = "${MACX}" ]; then
          echo "Setting IP for ${ETH} to ${IPRS}"
          F="/etc/sysconfig/network-scripts/ifcfg-${ETH}"
          /bin/set_key_value "${F}" "BOOTPROTO" "static"
          /bin/set_key_value "${F}" "ONBOOT" "yes"
          /bin/set_key_value "${F}" "IPADDR" "$(echo "${IPRS}" | cut -d/ -f1)"
          /bin/set_key_value "${F}" "NETMASK" "$(echo "${IPRS}" | cut -d/ -f2)"
          /bin/set_key_value "${F}" "GATEWAY" "$(echo "${IPRS}" | cut -d/ -f3)"
          /etc/rc.network restart ${ETH} >/dev/null 2>&1
          [ -n "$(echo "${IPRS}" | cut -d/ -f4)" ] && /etc/rc.network_routing "$(echo "${IPRS}" | cut -d/ -f4)" &
        fi
      done
    done
  fi  
}

if [ "${1}" = "patches" ]; then
    echo "Installing addon misc - ${1}"

    cp -vf /exts/misc/i915ids /usr/sbin/i915ids
    chmod +x /usr/sbin/i915ids

    case "${PLATFORM}" in
    apollolake)
        fixintelgpu
        ;;
    geminilake)
        fixintelgpu
        ;;
    esac

    fixnetwork

elif [ "${1}" = "late" ]; then
    echo "Installing addon misc - ${1}"
    echo "Script for fixing missing HW features dependencies"

    #cp -vf /exts/misc/sed /tmpRoot/usr/bin/sed
    #chmod +x /tmpRoot/usr/bin/sed

    fixacpibutton
    
    case "${PLATFORM}" in

    apollolake)
        copyintelgpu
        ;;
    geminilake)
        copyintelgpu
        ;;
    denverton)
        fixnvidia
        ;;

    esac

    fixcpufreq
    fixcrypto
    fixsdcard    
    fixservice

  # packages
  if [ ! -f /tmpRoot/usr/syno/etc/packages/feeds ]; then
    mkdir -p /tmpRoot/usr/syno/etc/packages
    echo '[{"feed":"https://spk7.imnks.com","name":"imnks"},{"feed":"https://packages.synocommunity.com","name":"synocommunity"}]' >/tmpRoot/usr/syno/etc/packages/feeds
  fi    
fi
