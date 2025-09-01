#!/usr/bin/env ash

if [ "${1}" = "late" ]; then
  echo "udma-crc-check - ${1}"
  echo "Installing udma-crc-check scripts and service"
  
  cp -vf check_udma_crc.sh /tmpRoot/usr/sbin/check_udma_crc.sh
  chmod 755 /tmpRoot/usr/sbin/check_udma_crc.sh
  
  mkdir -p /tmpRoot/etc/systemd/system/udma-crc-check.target.wants
  ln -sf /etc/systemd/system/udma-crc-check.service /tmpRoot/etc/systemd/system/multi-user.target.wants/udma-crc-check.service
fi
