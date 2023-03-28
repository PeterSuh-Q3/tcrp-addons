#
# Checking modules is loaded
#

echo -n "Loading module rtc_cmos -> "

if [ `/sbin/lsmod |grep -i rtc_cmos|wc -l` -gt 0 ]; then
        echo "Module rtc_cmos loaded succesfully"
        else echo "Module rtc_cmos is not loaded "
fi
