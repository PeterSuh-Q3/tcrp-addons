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

  mkdir -p "/tmpRoot/usr/lib/systemd/system"
  mkdir -p /tmpRoot/usr/lib/systemd/system/multi-user.target.wants

  # 이름을 분리하기 전(vmtools.service 하나로 VMware/QEMU를 겸용) 빌드로 이미
  # 설치된 시스템 위에, DSM을 새로 설치하지 않고 addon만 재빌드해서 덮어씌우면
  # 예전 유닛 파일이 지워지지 않고 그대로 남는다 - mev= 판정이 바뀌지 않는 한
  # 항상 같은 이름이 재생성될 뿐이라 못 느꼈지만, 이번 분리로 새 이름
  # (mshell-qemu-guest-agent.service)이 생겨도 예전 vmtools.service 가 같은
  # /dev/virtio-ports/org.qemu.guest_agent.0 를 놓고 계속 경쟁하며 크래시
  # 루프를 도는 것이 실기에서 확인됐다(2026-08-27). 아래에서 두 이름 모두
  # 무조건 먼저 지우고, 이번 mev= 에 맞는 쪽만 다시 만든다.
  rm -f /tmpRoot/usr/lib/systemd/system/vmtools.service
  rm -f /tmpRoot/usr/lib/systemd/system/mshell-qemu-guest-agent.service
  rm -f /tmpRoot/usr/lib/systemd/system/multi-user.target.wants/vmtools.service
  rm -f /tmpRoot/usr/lib/systemd/system/multi-user.target.wants/mshell-qemu-guest-agent.service

  # VMware Tools 와 QEMU guest agent 는 서로 다른 하이퍼바이저를 위한 완전히
  # 별개의 데몬인데, 예전엔 둘 다 "vmtools.service"라는 같은 이름으로 만들어져
  # 있어서 systemctl status/journalctl로는 지금 이게 어느 쪽인지 유닛 내용을
  # 열어보기 전엔 알 수 없었다(진단할 때 실제로 혼란을 유발함, 2026-08-27).
  # 유닛 이름 자체를 분리해 어느 쪽이 켜져 있는지 이름만 보고 바로 알 수 있게
  # 한다. mev=(빌드 시점의 /proc/cmdline)에 맞는 쪽만 만들고 enable한다.
  if grep -Eq 'mev=vmware' /proc/cmdline; then
    VMTOOLS_PID="/var/run/vmtools.pid"
    DEST="/tmpRoot/usr/lib/systemd/system/vmtools.service"
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
      echo "Description=mshell addon VMware Tools daemon"
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

    ln -sf /usr/lib/systemd/system/vmtools.service /tmpRoot/usr/lib/systemd/system/multi-user.target.wants/vmtools.service

  elif grep -Eq 'mev=kvm|mev=qemu' /proc/cmdline; then
    QGA_PID="/var/run/mshell-qemu-guest-agent.pid"
    DEST="/tmpRoot/usr/lib/systemd/system/mshell-qemu-guest-agent.service"
    GUEST_AGENT="/dev/virtio-ports/org.qemu.guest_agent.0"
    {
      echo "[Unit]"
      echo "Description=mshell addon QEMU guest agent daemon"
      echo "IgnoreOnIsolate=true"
      echo "After=multi-user.target"
      echo "ConditionPathExists=${GUEST_AGENT}"
      # SynoCommunity QEMU Guest Agent (SPK id: qemu-ga) owns the same
      # virtio serial port.  When that package is installed, skip this addon
      # unit cleanly rather than starting a second qemu-ga daemon that races
      # for /dev/virtio-ports/org.qemu.guest_agent.0.
      echo "ConditionPathExists=!/var/packages/qemu-ga/target/bin/qemu-ga"
      echo
      echo "[Service]"
      echo "Type=forking"
      echo "PIDFile=${QGA_PID}"
      echo "Environment=\"PATH=${VMTOOLS_PATH}/bin:${VMTOOLS_PATH}/sbin:\$PATH\""
      echo "Environment=\"LD_LIBRARY_PATH=${VMTOOLS_PATH}/lib:\$LD_LIBRARY_PATH\""
      echo "ExecStart=${VMTOOLS_PATH}/bin/qemu-ga -m virtio-serial -p ${GUEST_AGENT} -t /var/run/ -d -f ${QGA_PID}"
      echo "ExecReload=/bin/kill -HUP \$MAINPID"
      echo "Restart=always"
      echo "RestartSec=10"
      echo
      echo "[Install]"
      echo "WantedBy=multi-user.target"
    } >"${DEST}"

    ln -sf /usr/lib/systemd/system/mshell-qemu-guest-agent.service /tmpRoot/usr/lib/systemd/system/multi-user.target.wants/mshell-qemu-guest-agent.service

  else
    echo "vmtools: unknown mev, no VMware Tools / QEMU guest agent service installed"
  fi
fi
