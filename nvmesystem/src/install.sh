#!/usr/bin/env ash
#
# Copyright (C) 2023 PeterSuh-Q3 <https://github.com/PeterSuh-Q3>
#
# This is free software, licensed under the MIT License.
# See /LICENSE for more information.
#
# From：jim3ma, https://jim.plus/blog/post/jim/synology-installation-with-nvme-disks-only
#

# PLATFORMS="epyc7002"
# PLATFORM="$(/bin/get_key_value /etc.defaults/synoinfo.conf unique | cut -d"_" -f2)"
# if ! echo "${PLATFORMS}" | grep -wq "${PLATFORM}"; then
#   echo "${PLATFORM} is not supported nvmesystem addon!"
#   exit 0
# fi
_BUILD="$(/bin/get_key_value /etc.defaults/VERSION buildnumber)"
if [ ${_BUILD:-64570} -lt 69057 ]; then
  echo "${_BUILD} is not supported nvmesystem addon!"
  exit 0
fi

PLATFORMS="epyc7002 geminilake v1000 r1000"
PLATFORM="$(/bin/get_key_value /etc.defaults/synoinfo.conf unique | cut -d"_" -f2)"

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
  [ ! -f "${SO_FILE}.bak" ] && cp -pf "${SO_FILE}" "${SO_FILE}.bak"
  cp -f "${SO_FILE}" "${SO_FILE}.tmp"
  xxd -c $(xxd -p "${SO_FILE}.tmp" 2>/dev/null | wc -c) -p "${SO_FILE}.tmp" 2>/dev/null |
    sed "s/4584ed74b7488b4c24083b01/4584ed75b7488b4c24083b01/" |
    xxd -r -p >"${SO_FILE}" 2>/dev/null
  rm -f "${SO_FILE}.tmp"

elif [ "${1}" = "late" ]; then
  echo "Installing addon nvmesystem - ${1}"

  # disk/shared_disk_info_enum.c::84 Failed to allocate list in SharedDiskInfoEnum, errno=0x900.
  SO_FILE="/tmpRoot/usr/lib/libhwcontrol.so.1"
  [ ! -f "${SO_FILE}.bak" ] && cp -pf "${SO_FILE}" "${SO_FILE}.bak"

  cp -pf "${SO_FILE}" "${SO_FILE}.tmp"
  if echo "${PLATFORMS}" | grep -qw "${PLATFORM}"; then
      xxd -c $(xxd -p "${SO_FILE}.tmp" 2>/dev/null | wc -c) -p "${SO_FILE}.tmp" 2>/dev/null |
      sed "s/0f95c00fb6c0488b94240810/0f94c00fb6c0488b94240810/; s/8944240c8b44240809e84409/8944240c8b44240890904409/" |
      xxd -r -p >"${SO_FILE}" 2>/dev/null
  else    
    # Activate nvmevolume for Non-DT flatforms
      xxd -c $(xxd -p "${SO_FILE}.tmp" | wc -c) -p "${SO_FILE}.tmp" | 
      sed "s/803e00b801000000752.488b/803e00b8010000009090488b/" | 
      xxd -r -p > "${SO_FILE}"
  fi  
  rm -f "${SO_FILE}.tmp"  

  # Create storage pool page without RAID type.
  cp -vpf nvmesystem.sh /tmpRoot/usr/sbin/nvmesystem.sh
  chmod +x /tmpRoot/usr/sbin/nvmesystem.sh

  [ ! -f "/tmpRoot/usr/bin/gzip" ] && cp -vpf /usr/bin/gzip /tmpRoot/usr/bin/gzip  

  cat > /tmpRoot/etc/systemd/system/nvmesystem.service <<'EOF'
[Unit]
Description=mshell addon nvmesystem daemon
Wants=smpkg-custom-install.service pkgctl-StorageManager.service
After=smpkg-custom-install.service
After=storagepanel.service
[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/sbin/nvmesystem.sh
[Install]
WantedBy=multi-user.target
EOF

  mkdir -vp /tmpRoot/etc/systemd/system/multi-user.target.wants
  ln -vsf /etc/systemd/system/nvmesystem.service /tmpRoot/etc/systemd/system/multi-user.target.wants/nvmesystem.service

elif [ "${1}" = "rcExit" ]; then
  echo "Installing addon nvmesystem - ${1}"
  echo "Modifying /linuxrc.syno.impl nvmesystem - ${1}"
  sed -i 's/WithInternal=0/WithInternal=1/' /linuxrc.syno.impl
  cat /linuxrc.syno.impl | grep WithInternal

fi
