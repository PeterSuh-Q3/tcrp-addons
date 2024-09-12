#!/bin/sh

PLATFORM="$(uname -u | cut -d '_' -f2)"

cp -vf /exts/misc/sed /tmpRoot/usr/bin/sed
chmod +x /tmpRoot/usr/bin/sed

cp -vf /exts/misc/i915ids /usr/sbin/i915ids
chmod +x /usr/sbin/i915ids

SED_PATH='/tmpRoot/usr/bin/sed'
XXD_PATH='/tmpRoot/usr/bin/xxd'
LSPCI_PATH='/tmpRoot/usr/bin/lspci'

fixcpufreq() {

    if [ $(mount 2>/dev/null | grep sysfs | wc -l) -eq 0 ]; then
        mount -t sysfs sysfs /sys
        [ -f /usr/lib/modules/processor.ko ] && insmod /tmpRoot/usr/lib/modules/processor.ko
        [ -f /usr/lib/modules/acpi-cpufreq.ko ] && insmod /tmpRoot/usr/lib/modules/acpi-cpufreq.ko
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
  echo "replace ingel gpu info for i915le10th"

  if [ -f /tmpRoot/usr/lib/modules-load.d/70-video-kernel.conf ] && [ -f /tmpRoot/usr/lib/modules/i915.ko ]; then
    export LD_LIBRARY_PATH=/tmpRoot/usr/bin:/tmpRoot/usr/lib:${LD_LIBRARY_PATH}
    GPU="$(${LSPCI_PATH} -n | grep 0300 | grep 8086 | cut -d " " -f 3 | ${SED_PATH} -e 's/://g')"
    echo "${GPU}" >/tmpRoot/root/i915.GPU
    if [ -n "${GPU}" -a $(echo -n "${GPU}" | wc -c) -eq 8 ]; then
      if [ $(grep -i ${GPU} /usr/sbin/i915ids | wc -l) -eq 0 ]; then
        echo "Intel GPU is not detected (${GPU}), nothing to do"
        #${SED_PATH} -i 's/^i915/# i915/g' /tmpRoot/usr/lib/modules-load.d/70-video-kernel.conf
      else
        GPU_DEF="86800000923e0000"
        GPU_BIN="${GPU:2:2}${GPU:0:2}0000${GPU:6:2}${GPU:4:2}0000"
        KO_SIZE="$(${XXD_PATH} -p /tmpRoot/usr/lib/modules/i915.ko | wc -c)"
        ${XXD_PATH} -c ${KO_SIZE} -p /tmpRoot/usr/lib/modules/i915.ko /tmpRoot/root/i915.ko.hex
        if [ $(grep -i "${GPU_BIN}" /tmpRoot/root/i915.ko.hex | wc -l) -gt 0 ]; then
          echo "Intel GPU is detected (${GPU}), already support"
        else
          echo "Intel GPU is detected (${GPU}), replace id"
          if [ ! -f /tmpRoot/usr/lib/modules/i915.ko.bak ]; then
            cp -f /tmpRoot/usr/lib/modules/i915.ko /tmpRoot/usr/lib/modules/i915.ko.bak
          fi
          ${SED_PATH} -i "s/${GPU_DEF}/${GPU_BIN}/; s/308201f706092a86.*70656e6465647e0a//" /tmpRoot/root/i915.ko.hex
          if [ -n "$(cat /tmpRoot/root/i915.ko.hex)" ]; then
            ${XXD_PATH} -r -p /tmpRoot/root/i915.ko.hex >/tmpRoot/usr/lib/modules/i915.ko
            rm -f /tmpRoot/root/i915.ko.hex

            rmmod i915
            /tmpRoot/usr/sbin/depmod -a
            modprobe i915
            sleep 1
            
            if [ `/tmpRoot/sbin/lsmod |grep -i i915|wc -l` -gt 0 ] ; then
                echo "Module i915 loaded(modprobe) succesfully"
            else
                insmod /tmpRoot/usr/lib/modules/i915.ko            
            fi            
          else
            echo "Intel GPU is detected (${GPU}), replace i915.ko error"
          fi
        fi
      fi
    fi
  fi
  
}

fixacpibutton() {
    #button.ko

    if [ ! -d /proc/acpi ]; then
        echo "NO ACPI status is available, disabling button.ko"
        ${SED_PATH} -i 's/^button/# button/g' /tmpRoot/usr/lib/modules-load.d/70-video-kernel.conf
    fi

}

if [ "${1}" = "late" ]; then
    echo "Script for fixing missing HW features dependencies"

    fixacpibutton
    
    case "${PLATFORM}" in

    bromolow)
        fixcpufreq
        fixcrypto
        ;;
    apollolake)
        fixcpufreq
        fixcrypto
        fixintelgpu
        ;;
    broadwell)
        fixcpufreq
        fixcrypto
        ;;
    broadwellnk)
        fixcpufreq
        fixcrypto
        ;;
    v1000)
        fixcpufreq
        fixcrypto
        ;;
    r1000)
        fixcpufreq
        fixcrypto
        ;;
    denverton)
        fixcpufreq
        fixcrypto
        fixnvidia
        ;;
    geminilake)
        fixcpufreq
        fixcrypto
        fixintelgpu
        ;;
    epyc7002)
        fixcpufreq
        fixcrypto
        fixnvidia 
    *)
        fixcpufreq
        fixcrypto
        ;;

    esac
fi
