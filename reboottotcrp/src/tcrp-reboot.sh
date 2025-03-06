#!/bin/sh
echo "Change the default of grub.cfg boot menu to Tinycore Loader Build in M-SHELL"
if [ ! -d /mnt/tcrp-p1 ]; then
  mkdir /mnt/tcrp-p1
fi  

mount -o loop /dev/synoboot1 /mnt/tcrp-p1
cd /mnt/tcrp-p1
sed -i "s/set default=\"[0-9]\"/set default=\"1\"/g" /mnt/tcrp-p1/boot/grub/grub.cfg
cd /mnt
umount /mnt/tcrp-p1
