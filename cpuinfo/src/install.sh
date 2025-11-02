#!/bin/bash

if [ "${1}" = "late" ]; then
  echo "Installing daemon for CPU Info"
  
  cp -vpf cpuinfo.sh /tmpRoot/usr/sbin/cpuinfo.sh
  chmod 755 /tmpRoot/usr/sbin/cpuinfo.sh

  shift
  mkdir -p "/tmpRoot/usr/lib/systemd/system"
  DEST="/tmpRoot/usr/lib/systemd/system/cpuinfo.service"
  {
    echo "[Unit]"
    echo "Description=MSHELL addon cpuinfo daemon"
    echo "After=synoscgi.service nginx.service"
    echo
    echo "[Service]"
    echo "Type=oneshot"
    echo "RemainAfterExit=yes"
    echo "ExecStart=-/usr/sbin/cpuinfo.sh" "$@"
    echo
    echo "[Install]"
    echo "WantedBy=multi-user.target"
  } >"${DEST}"
  
  mkdir -p /tmpRoot/usr/lib/systemd/system/multi-user.target.wants
  ln -sf /usr/lib/systemd/system/cpuinfo.service /tmpRoot/usr/lib/systemd/system/multi-user.target.wants/cpuinfo.service

  # synoscgiproxy
  tar -zxvf synoscgiproxy.tgz -C /tmpRoot/usr/sbin
  
fi
