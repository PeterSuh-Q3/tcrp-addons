#!/bin/sh

echo "Script for fixing missing HW features dependencies"

PLATFORM="$(uname -u | cut -d '_' -f2)"

cp /exts/misc/sed /tmpRoot/usr/bin/sed
chmod +x /tmpRoot/usr/bin/sed

SED_PATH='/tmpRoot/usr/bin/sed'

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
        NVIDIADEV=$(cat /proc/bus/pci/devices | grep -i 10de | wc -l)
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
    GPU="$(LD_LIBRARY_PATH=/tmpRoot/lib64 /tmpRoot/bin/lspci -n | grep 0300 | cut -d " " -f 3 | sed -e 's/://g')"
    if [ -f /tmpRoot/usr/lib/modules-load.d/70-video-kernel.conf ]; then
        INTELGPU=$(grep -i ${GPU} /exts/misc/pciids | wc -l)
        if [ $INTELGPU -eq 0 ]; then
            echo "Intel GPU is not detected ($GPU), disabling "
            ${SED_PATH} -i 's/^i915/# i915/g' /tmpRoot/usr/lib/modules-load.d/70-video-kernel.conf
        else
            echo "Intel GPU is detected ($GPU), nothing to do"
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

case "${PLATFORM}" in

bromolow)
    fixcpufreq
    fixcrypto
    ;;
apollolake)
    fixcpufreq
    fixcrypto
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
    fixacpibutton
    ;;

*)
    fixcpufreq
    fixcrypto
    ;;

esac
