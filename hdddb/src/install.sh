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

  mkdir -p "/tmpRoot/usr/lib/systemd/system"
  DEST="/tmpRoot/usr/lib/systemd/system/hdddb.service"
  {
    echo "[Unit]"
    echo "Description=MSHELL addon hdddb daemon"
    echo "Wants=smpkg-custom-install.service pkgctl-StorageManager.service"
    echo "After=smpkg-custom-install.service"
    echo
    echo "[Service]"
    echo "Type=oneshot"
    echo "RemainAfterExit=yes"
    echo "ExecStart=-/usr/sbin/hdddb.sh -nrwpeSI"
    echo
    echo "[Install]"
    echo "WantedBy=multi-user.target"
  } >"${DEST}"

  mkdir -vp /tmpRoot/usr/lib/systemd/system/multi-user.target.wants
  ln -vsf /usr/lib/systemd/system/hdddb.service /tmpRoot/usr/lib/systemd/system/multi-user.target.wants/hdddb.service
fi
