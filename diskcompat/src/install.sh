#!/usr/bin/env ash
#
# Ported from RROrg/rr-addons (diskcompat), MIT License.
# https://github.com/RROrg/rr-addons/tree/main/diskcompat
#

if [ "${1}" = "late" ]; then
  echo "Installing addon diskcompat - ${1}"
  cp -vpf diskcompat.sh /tmpRoot/usr/bin/diskcompat.sh
  chmod +x /tmpRoot/usr/bin/diskcompat.sh

  mkdir -p "/tmpRoot/usr/lib/systemd/system"
  DEST="/tmpRoot/usr/lib/systemd/system/diskcompat.service"
  {
    echo "[Unit]"
    echo "Description=MSHELL addon diskcompat daemon"
    echo "Wants=smpkg-custom-install.service pkgctl-StorageManager.service"
    echo "After=smpkg-custom-install.service pkgctl-StorageManager.service"
    echo
    echo "[Service]"
    echo "Type=oneshot"
    echo "RemainAfterExit=yes"
    echo "ExecStart=-/usr/bin/diskcompat.sh"
    echo
    echo "[Install]"
    echo "WantedBy=multi-user.target"
  } >"${DEST}"

  mkdir -p /tmpRoot/usr/lib/systemd/system/multi-user.target.wants
  ln -sf /usr/lib/systemd/system/diskcompat.service /tmpRoot/usr/lib/systemd/system/multi-user.target.wants/diskcompat.service
fi
