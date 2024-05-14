#!/usr/bin/env ash
#
# Copyright (C) 2023 PeterSuh-Q3 <https://github.com/PeterSuh-Q3>
#
# This is free software, licensed under the MIT License.
# See /LICENSE for more information.
#
# From：jim3ma, https://jim.plus/blog/post/jim/synology-installation-with-nvme-disks-only
#
tmpRoot="/tmpRoot"

if [ "${1}" = "early" ]; then
  echo "Installing addon nvmesystem - ${1}"

  [ ! -f "/usr/sbin/xxd" ] && cp -vf xxd /usr/sbin/xxd
  chmod +x /usr/sbin/xxd
  [ ! -f "/usr/sbin/sed" ] && cp -vf sed /usr/sbin/sed
  chmod +x /usr/sbin/sed

  # System volume is assembled with SSD Cache only, please remove SSD Cache and then reboot
  sed -i "s/support_ssd_cache=.*/support_ssd_cache=\"no\"/" /etc/synoinfo.conf /etc.defaults/synoinfo.conf

  # [CREATE][failed] Raidtool initsys
  SO_FILE="/usr/syno/bin/scemd"
  [ ! -f "${SO_FILE}.bak" ] && cp -vf "${SO_FILE}" "${SO_FILE}.bak"
  cp -f "${SO_FILE}" "${SO_FILE}.tmp"
  xxd -c $(xxd -p "${SO_FILE}.tmp" | wc -c) -p "${SO_FILE}.tmp" |
    sed "s/4584ed74b7488b4c24083b01/4584ed75b7488b4c24083b01/" |
    xxd -r -p >"${SO_FILE}"
  rm -f "${SO_FILE}.tmp"

elif [ "${1}" = "late" ]; then
  echo "Installing addon nvmesystem - ${1}"

  # System volume is assembled with SSD Cache only, please remove SSD Cache and then reboot
  ${tmpRoot}/usr/bin/sed -i "s/support_ssd_cache=.*/support_ssd_cache=\"no\"/" ${tmpRoot}/etc/synoinfo.conf ${tmpRoot}/etc.defaults/synoinfo.conf

  # disk/shared_disk_info_enum.c::84 Failed to allocate list in SharedDiskInfoEnum, errno=0x900.
  SO_FILE="${tmpRoot}/usr/lib/libhwcontrol.so.1"
  [ ! -f "${SO_FILE}.bak" ] && cp -vf "${SO_FILE}" "${SO_FILE}.bak"

  cp -vf "${SO_FILE}" "${SO_FILE}.tmp"

  ${tmpRoot}/usr/bin/xxd -c $(${tmpRoot}/usr/bin/xxd -p "${SO_FILE}.tmp" | wc -c) -p "${SO_FILE}.tmp" | 
    sed "s/0f95c00fb6c0488b94240810/0f94c00fb6c0488b94240810/; s/8944240c8b44240809e84409/8944240c8b44240890904409/; s/803e00b8010000007524488b/803e00b8010000009090488b/" | 
    ${tmpRoot}/usr/bin/xxd -r -p > "${SO_FILE}"
  rm -f "${SO_FILE}.tmp"

  # Create storage pool page without RAID type.
  cp -vf nvmesystem.sh ${tmpRoot}/usr/sbin/nvmesystem.sh
  chmod +x ${tmpRoot}/usr/sbin/nvmesystem.sh

  cat > ${tmpRoot}/etc/systemd/system/nvmesystem.service <<'EOF'
[Unit]
Description=Modify storage panel, from wjz304
After=multi-user.target
After=synoscgi.service
After=storagepanel.service
[Service]
Type=oneshot
RemainAfterExit=true
ExecStart=/usr/sbin/nvmesystem.sh
[Install]
WantedBy=multi-user.target
EOF

  mkdir -vp ${tmpRoot}/etc/systemd/system/multi-user.target.wants
  ln -vsf /etc/systemd/system/nvmesystem.service ${tmpRoot}/etc/systemd/system/multi-user.target.wants/nvmesystem.service

elif [ "${1}" = "rcExit" ]; then
  echo "Installing addon nvmesystem - ${1}"
  echo "Modifying /linuxrc.syno.impl nvmesystem - ${1}"
  sed -i 's/WithInternal=0/WithInternal=1/' /linuxrc.syno.impl
  cat /linuxrc.syno.impl | grep WithInternal

fi
