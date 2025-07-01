#!/usr/bin/env sh
#
# Copyright (C) 2022 Ing <https://github.com/wjz304>
#
# This is free software, licensed under the MIT License.
# See /LICENSE for more information.
#

if [ "${1}" = "late" ]; then
  echo "Installing addon apppatch - ${1}"

  cp -vpf /usr/bin/PatchELFSharp /tmpRoot/usr/bin/PatchELFSharp
  cp -vpf /usr/bin/apppatch.sh /tmpRoot/usr/bin/apppatch.sh

  mkdir -p "/tmpRoot/usr/lib/systemd/system"
  DEST="/tmpRoot/usr/lib/systemd/system/apppatch.service"
  {
    echo "[Unit]"
    echo "Description=mshell addon apppatch daemon"
    echo "Wants=smpkg-custom-install.service pkgctl-StorageManager.service"
    echo "After=smpkg-custom-install.service"
    # echo "ConditionPathExists=|/var/packages/SynologyPhotos"
    # echo "ConditionPathExists=|/var/packages/SurveillanceStation"
    echo
    echo "[Service]"
    echo "Type=oneshot"
    echo "RemainAfterExit=no"
    echo "ExecStart=-/usr/bin/apppatch.sh"
    echo
    echo "[Install]"
    echo "WantedBy=multi-user.target"
  } >"${DEST}"

  mkdir -vp /tmpRoot/usr/lib/systemd/system/multi-user.target.wants
  ln -vsf /usr/lib/systemd/system/apppatch.service /tmpRoot/usr/lib/systemd/system/multi-user.target.wants/apppatch.service

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

  mkdir -vp /tmpRoot/usr/lib/systemd/system/multi-user.target.wants
  ln -vsf /usr/lib/systemd/system/apppatch.path /tmpRoot/usr/lib/systemd/system/multi-user.target.wants/apppatch.path

fi
