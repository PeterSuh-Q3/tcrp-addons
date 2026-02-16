#!/usr/bin/env sh
#
# Copyright (C) 2022 Ing <https://github.com/wjz304>
#
# This is free software, licensed under the MIT License.
# See /LICENSE for more information.
#

if [ "${1}" = "late" ]; then
  echo "Installing addon vmtools - ${1}"

  mkdir -p /tmpRoot/usr/vmtools
  tar -zxf ./vmtools-7.1.tgz -C /tmpRoot/usr/vmtools
  ln -sf /usr/vmtools/etc/vmware-tools /tmpRoot/usr/vmtools/etc/vmware-tools
  ln -sf /usr/vmtools/lib/open-vm-tools /tmpRoot/usr/vmtools/lib/open-vm-tools
  ln -sf /usr/vmtools/share/open-vm-tools /tmpRoot/usr/vmtools/share/open-vm-tools

  VMTOOLS_PATH="/usr/vmtools"
  VMTOOLS_PID="/var/run/vmtools.pid"

  mkdir -p "/tmpRoot/usr/lib/systemd/system"
  DEST="/tmpRoot/usr/lib/systemd/system/vmtools.service"

  if grep -Eq 'mev=vmware' /proc/cmdline; then
    VMWARE_CONF="${VMTOOLS_PATH}/etc/vmware-tools/tools.conf"
    COMMON_PATH="${VMTOOLS_PATH}/lib/open-vm-tools/plugins"
    PLUGINS_PATH="${COMMON_PATH}/vmsvc"

    mkdir -p /tmpRoot/usr/vmtools/etc/vmware-tools
    {
      echo "[vmtools]"
      echo "    disable-tools-version = false"
      echo "[logging]"
      echo "    log = true"
      echo "    vmsvc.level = debug"
      echo "    vmsvc.handler = file"
      echo "    vmsvc.data = /var/log/vmsvc.mshell.log"
      echo "    vmtoolsd.level = debug"
      echo "    vmtoolsd.handler = file"
      echo "    vmtoolsd.data = /var/log/vmtoolsd.mshell.log"
      echo "[powerops]"
      echo "    poweron-script = ${VMTOOLS_PATH}/etc/vmware-tools/poweron-vm-default"
      echo "    poweroff-script = ${VMTOOLS_PATH}/etc/vmware-tools/poweroff-vm-default"
      echo "    resume-script = ${VMTOOLS_PATH}/etc/vmware-tools/resume-vm-default"
      echo "    suspend-script = ${VMTOOLS_PATH}/etc/vmware-tools/suspend-vm-default"
    } >"/tmpRoot${VMWARE_CONF}"

    {
      echo "[Unit]"
      echo "Description=mshell addon vmtools daemon"
      echo "IgnoreOnIsolate=true"
      echo "After=multi-user.target"
      echo
      echo "[Service]"
      echo "Type=forking"
      echo "PIDFile=${VMTOOLS_PID}"
      echo "Environment=\"PATH=${VMTOOLS_PATH}/bin:${VMTOOLS_PATH}/sbin:\$PATH\""
      echo "Environment=\"LD_LIBRARY_PATH=${VMTOOLS_PATH}/lib:\$LD_LIBRARY_PATH\""
      echo "ExecStart=${VMTOOLS_PATH}/bin/vmtoolsd -c ${VMWARE_CONF} --common-path=${COMMON_PATH} --plugin-path=${PLUGINS_PATH} -b ${VMTOOLS_PID}"
      echo "ExecReload=/bin/kill -HUP \$MAINPID"
      echo "Restart=always"
      echo "RestartSec=10"
      echo
      echo "[Install]"
      echo "WantedBy=multi-user.target"
    } >"${DEST}"
  elif grep -Eq 'mev=kvm|mev=qemu' /proc/cmdline; then
    GUEST_AGENT="/dev/virtio-ports/org.qemu.guest_agent.0"
    {
      echo "[Unit]"
      echo "Description=mshell addon qemu-guest-agent daemon"
      echo "IgnoreOnIsolate=true"
      echo "After=multi-user.target"
      echo "ConditionPathExists=${GUEST_AGENT}"
      echo
      echo "[Service]"
      echo "Type=forking"
      echo "PIDFile=${VMTOOLS_PID}"
      echo "Environment=\"PATH=${VMTOOLS_PATH}/bin:${VMTOOLS_PATH}/sbin:\$PATH\""
      echo "Environment=\"LD_LIBRARY_PATH=${VMTOOLS_PATH}/lib:\$LD_LIBRARY_PATH\""
      echo "ExecStart=${VMTOOLS_PATH}/bin/qemu-ga -m virtio-serial -p ${GUEST_AGENT} -t /var/run/ -d -f ${VMTOOLS_PID}"
      echo "ExecReload=/bin/kill -HUP \$MAINPID"
      echo "Restart=always"
      echo "RestartSec=10"
      echo
      echo "[Install]"
      echo "WantedBy=multi-user.target"
    } >"${DEST}"
  else
    {
      echo "[Unit]"
      echo "Description=mshell addon vmtools daemon"
      echo "IgnoreOnIsolate=true"
      echo "After=multi-user.target"
      echo
      echo "[Service]"
      echo "Type=oneshot"
      # echo "Type=forking"
      # echo "PIDFile=${VMTOOLS_PID}"
      echo "Environment=\"PATH=${VMTOOLS_PATH}/bin:${VMTOOLS_PATH}/sbin:\$PATH\""
      echo "Environment=\"LD_LIBRARY_PATH=${VMTOOLS_PATH}/lib:\$LD_LIBRARY_PATH\""
      echo "ExecStart=-echo Unknown mev"
      # echo "ExecReload=/bin/kill -HUP \$MAINPID"
      # echo "Restart=always"
      # echo "RestartSec=10"
      echo
      echo "[Install]"
      echo "WantedBy=multi-user.target"
    } >"${DEST}"
    exit 0
  fi
  mkdir -p /tmpRoot/usr/lib/systemd/system/multi-user.target.wants
  ln -sf /usr/lib/systemd/system/vmtools.service /tmpRoot/usr/lib/systemd/system/multi-user.target.wants/vmtools.service
fi
