#!/bin/sh
echo "Change the default of grub.cfg boot menu to Tinycore Loader Build in M-SHELL"
mkdir /mnt/tcrp-p1
cd /dev/
mount -t vfat synoboot1 /mnt/tcrp-p1
cd /mnt/tcrp-p1
if [ $(cat /mnt/tcrp-p1/boot/grub/grub.cfg | grep Verbose | wc -l ) -gt 0 ]; then
echo "For Jot Mode"
sed -i "s/set default=\"[0-9]\"/set default=\"3\"/g" /mnt/tcrp-p1/boot/grub/grub.cfg
else
echo "For Friend Mode"
sed -i "s/set default=\"[0-9]\"/set default=\"1\"/g" /mnt/tcrp-p1/boot/grub/grub.cfg
fi
cd /mnt
umount /mnt/tcrp-p1
