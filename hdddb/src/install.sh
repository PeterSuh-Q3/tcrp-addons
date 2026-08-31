#!/usr/bin/env ash
#
# Copyright (C) 2022 Ing <https://github.com/wjz304>
#
# This is free software, licensed under the MIT License.
# See /LICENSE for more information.
#

if [ "${1}" = "late" ]; then
  echo "Installing addon hdddb - ${1}"
  cp -f hdddb.sh /tmpRoot/usr/sbin/hdddb.sh
  chmod +x /tmpRoot/usr/sbin/hdddb.sh

  # systemd loads /etc/systemd/system/<unit> in preference to
  # /usr/lib/systemd/system/<unit> of the same name. Some older
  # loaders (RR/ARC/early MSHELL builds) dropped hdddb.service
  # directly into /etc/systemd/system instead of /usr/lib/systemd/system.
  # That leftover file survives every later DSM update and model
  # migration untouched (real-hardware case: DS425+ -> DS925+ migration
  # carried an /etc/systemd/system/hdddb.service dated 2025-02-15 forward
  # unchanged), and permanently shadows whatever this script installs
  # below no matter how many times the addon/loader is rebuilt - the
  # box kept running the old hardcoded "-nfre" instead of the current
  # "-nrwpeSI --autoupdate=0". Remove any such override before writing
  # our own copy, so a fresh install/migration self-heals this.
  if [ -f "/tmpRoot/etc/systemd/system/hdddb.service" ]; then
    echo "Removing stale /etc/systemd/system/hdddb.service override from an earlier loader"
    rm -f "/tmpRoot/etc/systemd/system/hdddb.service"
  fi

  mkdir -p "/tmpRoot/usr/lib/systemd/system"
  DEST="/tmpRoot/usr/lib/systemd/system/hdddb.service"
  {
    echo "[Unit]"
    echo "Description=MSHELL addon hdddb daemon"
    echo "Wants=smpkg-custom-install.service pkgctl-StorageManager.service"
    echo "After=smpkg-custom-install.service pkgctl-StorageManager.service"
    echo
    echo "[Service]"
    echo "Type=oneshot"
    echo "RemainAfterExit=yes"
    echo "ExecStart=/bin/bash -c 'sleep 30 && /usr/sbin/hdddb.sh -nrwpeSI --autoupdate=0 > /var/log/hdddb_firstboot.log 2>&1'"
    echo
    echo "[Install]"
    echo "WantedBy=multi-user.target"
  } >"${DEST}"

  mkdir -p /tmpRoot/usr/lib/systemd/system/multi-user.target.wants
  ln -sf /usr/lib/systemd/system/hdddb.service /tmpRoot/usr/lib/systemd/system/multi-user.target.wants/hdddb.service
fi
