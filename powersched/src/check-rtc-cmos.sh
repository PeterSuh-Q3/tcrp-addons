#!/usr/bin/env ash
#
# Checking modules is loaded
#

if [ "${1}" = "modules" ]; then
    insmod /lib/modules/rtc-cmos.ko

    echo -n "Check Loading module rtc_cmos -> "

    if [ `/sbin/lsmod |grep -i rtc_cmos|wc -l` -gt 0 ]; then
            echo "Module rtc_cmos loaded succesfully"
            else echo "Module rtc_cmos is not loaded "
    fi
fi
