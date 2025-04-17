#!/usr/bin/env bash
#
# Copyright (C) 2022 Ing <https://github.com/wjz304>
#
# This is free software, licensed under the MIT License.
# See /LICENSE for more information.
#

# email
# cat /usr/syno/etc/synosmtp.conf
# gvfs
# ls /var/tmp/user/1026/gvfs/  /usr/syno/etc/synovfs/1026

NUM="${1:-7}"
PRE="${2:-bkp}"

SCBKPATH="/usr/mshell/scbk"
FILENAME="${PRE}_$(date +%Y%m%d%H%M%S).dss"
mkdir -p "${SCBKPATH}"
/usr/syno/bin/synoconfbkp export --filepath="${SCBKPATH}/${FILENAME}"
echo "Backup to ${SCBKPATH}/${FILENAME}"

for I in $(ls ${SCBKPATH}/${PRE}*.dss | sort -r | awk "NR>${NUM}"); do
  rm -f "${I}"
done

LOADER_DISK_PART1="/dev/synoboot1"
if [ ! -b "${LOADER_DISK_PART1}" ]; then
  echo "Boot disk not found"
  exit 1
fi

echo 1 >/proc/sys/kernel/syno_install_flag 2>/dev/null
WORK_PATH="/mnt/p1"
mkdir -p "${WORK_PATH}"
mount | grep -q "${LOADER_DISK_PART1}" && umount "${LOADER_DISK_PART1}" 2>/dev/null || true
mount -o loop "${LOADER_DISK_PART1}" "${WORK_PATH}" || {
  echo "Can't mount ${LOADER_DISK_PART1}."
  echo 0 >/proc/sys/kernel/syno_install_flag 2>/dev/null
  exit 1
}

rm -rf "${WORK_PATH}/scbk"
cp -rf "${SCBKPATH}" "${WORK_PATH}"

sync

umount "${WORK_PATH}" 2>/dev/null

echo 0 >/proc/sys/kernel/syno_install_flag 2>/dev/null

echo "Backup to /mnt/p1/scbk/"

exit 0
