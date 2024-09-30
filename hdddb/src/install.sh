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

  echo "Excute hdddb.sh with option n."
  /tmpRoot/usr/sbin/hdddb.sh -n

  mkdir -p "/tmpRoot/etc/systemd/system"
  DEST="/tmpRoot/etc/systemd/system/hdddb.service"
  echo "[Unit]"                                    >${DEST}
  echo "Description=HDDs/SSDs drives databases"   >>${DEST}
  echo "After=multi-user.target"                  >>${DEST}
  echo                                            >>${DEST}
  echo "[Service]"                                >>${DEST}
  echo "Type=oneshot"                             >>${DEST}
  echo "RemainAfterExit=yes"                      >>${DEST}
  echo "ExecStart=/usr/sbin/hdddb.sh -nfreS"      >>${DEST}
  echo                                            >>${DEST}
  echo "[Install]"                                >>${DEST}
  echo "WantedBy=multi-user.target"               >>${DEST}

  mkdir -vp /tmpRoot/etc/systemd/system/multi-user.target.wants
  ln -vsf /etc/systemd/system/hdddb.service /tmpRoot/etc/systemd/system/multi-user.target.wants/hdddb.service
fi
