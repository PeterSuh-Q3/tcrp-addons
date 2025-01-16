#!/bin/bash

if [ "${1}" = "late" ]; then

  echo "Installing addon cpuinfo - ${1}"

  # cpuinfo
  cp -vpf cpuinfo.sh /tmpRoot/usr/bin/cpuinfo.sh

  shift
  mkdir -p "/tmpRoot/usr/lib/systemd/system"
  DEST="/tmpRoot/usr/lib/systemd/system/cpuinfo.service"
  {
    echo "[Unit]"
    echo "Description=MSHELL addon cpuinfo daemon"
    echo "After=multi-user.target"
    echo "After=synoscgi.service nginx.service"
    echo
    echo "[Service]"
    echo "Type=oneshot"
    echo "RemainAfterExit=yes"
    echo "ExecStart=-/usr/bin/cpuinfo.sh $@"
    echo
    echo "[Install]"
    echo "WantedBy=multi-user.target"
  } >"${DEST}"

  mkdir -vp /tmpRoot/usr/lib/systemd/system/multi-user.target.wants
  ln -vsf /usr/lib/systemd/system/cpuinfo.service /tmpRoot/usr/lib/systemd/system/multi-user.target.wants/cpuinfo.service

  # synoscgiproxy
  cp -vpf /usr/sbin/synoscgiproxy /tmpRoot/usr/sbin/synoscgiproxy

fi
