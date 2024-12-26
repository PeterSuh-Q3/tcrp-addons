#!/usr/bin/env ash
#
# Copyright (C) 2022 Ing <https://github.com/wjz304>
#
# This is free software, licensed under the MIT License.
# See /LICENSE for more information.
#

if [ "${1}" = "late" ]; then
  echo "Installing addon hdddb - ${1}"
  cp -vf hdddb.sh /tmpRoot/usr/sbin/hdddb.sh
  chmod +x /tmpRoot/usr/sbin/hdddb.sh

  echo "Add drive_db_test_url to synoinfo.conf"
  grep -q '^drive_db_test_url=' /tmpRoot/etc.defaults/synoinfo.conf || echo 'drive_db_test_url="127.0.0.1"' >> /tmpRoot/etc.defaults/synoinfo.conf
  grep -q '^drive_db_test_url=' /tmpRoot/etc/synoinfo.conf || echo 'drive_db_test_url="127.0.0.1"' >> /tmpRoot/etc/synoinfo.conf
  #echo "Excute hdddb.sh with option n."
  #/tmpRoot/usr/sbin/hdddb.sh -n

  mkdir -p "/tmpRoot/etc/systemd/system"
  DEST="/tmpRoot/etc/systemd/system/hdddb.service"
  {
    echo "[Unit]"
    echo "Description=mshell addon hdddb daemon"
    echo "Wants=smpkg-custom-install.service pkgctl-StorageManager.service"
    echo "After=smpkg-custom-install.service"
    echo
    echo "[Service]"
    echo "Type=oneshot"
    echo "RemainAfterExit=yes"
    echo "ExecStart=-/usr/bin/hdddb.sh -nrwpeS"
    echo
    echo "[Install]"
    echo "WantedBy=multi-user.target"
  } >"${DEST}"

  mkdir -vp /tmpRoot/etc/systemd/system/multi-user.target.wants
  ln -vsf /etc/systemd/system/hdddb.service /tmpRoot/etc/systemd/system/multi-user.target.wants/hdddb.service
fi
