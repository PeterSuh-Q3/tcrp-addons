#!/usr/bin/env ash
#
# Copyright (C) 2022 Ing <https://github.com/wjz304>
#
# This is free software, licensed under the MIT License.
# See /LICENSE for more information.
#

if [ "${1}" = "late" ]; then
  echo "Installing addon apppatch - ${1}"

  tar -zxvf ./PatchELFSharp.tgz -C /tmpRoot/usr/bin
  #cp -vpf ./PatchELFSharp /tmpRoot/usr/bin/PatchELFSharp
  cp -vpf ./apppatch.sh /tmpRoot/usr/bin/apppatch.sh

  mkdir -p "/tmpRoot/usr/lib/systemd/system"
  DEST="/tmpRoot/usr/lib/systemd/system/apppatch.service"
  {
    echo "[Unit]"
    echo "Description=mshell addon apppatch daemon"
    echo "Wants=smpkg-custom-install.service pkgctl-StorageManager.service"
    echo "After=smpkg-custom-install.service pkgctl-StorageManager.service"
    echo
    echo "[Service]"
    echo "Type=oneshot"
    echo "RemainAfterExit=no"
    echo "ExecStart=/bin/bash -c 'sleep 30 && /usr/bin/apppatch.sh > /var/log/apppatch_firstboot.log 2>&1'"
    echo
    echo "[Install]"
    echo "WantedBy=multi-user.target"
  } >"${DEST}"

  mkdir -p /tmpRoot/usr/lib/systemd/system/multi-user.target.wants
  ln -sf /usr/lib/systemd/system/apppatch.service /tmpRoot/usr/lib/systemd/system/multi-user.target.wants/apppatch.service

  DEST="/tmpRoot/usr/lib/systemd/system/apppatch.path"
  {
    echo "[Unit]"
    echo "Description=mshell addon apppatch path"
    echo "Wants=smpkg-custom-install.service pkgctl-StorageManager.service"
    echo "After=smpkg-custom-install.service"
    echo "ConditionPathExists=/var/packages"
    echo
    echo "[Path]"
    echo "PathModified=/var/packages"
    echo "Unit=apppatch.service"
    echo
    echo "[Install]"
    echo "WantedBy=multi-user.target"
  } >"${DEST}"

  mkdir -p /tmpRoot/usr/lib/systemd/system/multi-user.target.wants
  ln -sf /usr/lib/systemd/system/apppatch.path /tmpRoot/usr/lib/systemd/system/multi-user.target.wants/apppatch.path

fi
