#!/bin/bash

if [ "${1}" = "modules" ]; then
    echo "mac-spoof - modules"

    dmesg | grep "Kernel command line" >/tmp/cmdline.out
    while IFS=" " read -r line; do
        echo "$line" | sed 's/ /\n/g'
    done </tmp/cmdline.out | egrep -i "mac" | sort >/tmp/cmdline.check

    . /tmp/cmdline.check

    # Set custom MAC if defined 
    ethdevs=$(ls /sys/class/net/ | grep eth || true)
    I=1
    J=0
    for eth in $ethdevs; do
        HWADDR="$(ifconfig ${eth} | grep HWaddr | cut -d ' ' -f 11)"
        eval "usrmac=\${mac${I}}"
        MAC="${usrmac:0:2}:${usrmac:2:2}:${usrmac:4:2}:${usrmac:6:2}:${usrmac:8:2}:${usrmac:10:2}"
        if [ "${HWADDR}" != "${MAC}" ]; then
            echo "Setting MAC Address from ${HWADDR} to ${MAC} on ${eth}"
            /sbin/ip link set dev ${eth} address ${MAC}
            J=$((${J} + 1))
        fi
        I=$((${I} + 1))
        if [ "${eth}" = "eth4" ]; then
            break
        fi
    done

    if [ $J -gt 0 ]; then 
        echo "Restarting /etc/rc.network to renew IP..."
        /etc/rc.network restart >/dev/null 2>&1
    fi

elif [ "${1}" = "late" ]; then
    echo "mac-spoof - late"

fi
