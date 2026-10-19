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

PRE="${2:-bkp}"

SCBKPATH="/volume1/mshell/scbk"
FILENAME="${PRE}_$(date +%Y%m%d%H%M%S).dss"
LOADER_DISK_PART1="/dev/synoboot1"
if [ ! -b "${LOADER_DISK_PART1}" ]; then
  echo "Boot disk not found"
  exit 1
fi

WORK_PATH="/mnt/synoboot1"
INSTALL_FLAG="/proc/sys/kernel/syno_install_flag"
MOUNTED_BY_US=0
FLAG_SET=0

is_mounted() {
  awk -v target="$1" '$2 == target { found = 1 } END { exit !found }' /proc/mounts
}

# Invoked indirectly by the EXIT trap.
# shellcheck disable=SC2329
cleanup() {
  local result=$?
  trap - EXIT HUP INT TERM
  if [ "$MOUNTED_BY_US" -eq 1 ]; then
    sync || result=1
    umount "$WORK_PATH" || {
      echo "ERROR: Failed to unmount ${WORK_PATH}; inspect the mount before retrying." >&2
      result=1
    }
  fi
  if [ "$FLAG_SET" -eq 1 ]; then
    echo 0 >"$INSTALL_FLAG" 2>/dev/null || {
      echo "ERROR: Failed to reset syno_install_flag." >&2
      result=1
    }
  fi
  exit "$result"
}

fail() {
  echo "ERROR: $*" >&2
  exit 1
}

mkdir -p "$SCBKPATH" || fail "Cannot create ${SCBKPATH}."
/usr/syno/bin/synoconfbkp export --filepath="${SCBKPATH}/${FILENAME}" \
  || fail "synoconfbkp export failed."
[ -s "${SCBKPATH}/${FILENAME}" ] || fail "Exported backup is missing or empty."
echo "Backup created: ${SCBKPATH}/${FILENAME}"

mkdir -p "$WORK_PATH" || fail "Cannot create ${WORK_PATH}."
if is_mounted "$WORK_PATH" || awk -v source="$LOADER_DISK_PART1" '$1 == source { found = 1 } END { exit !found }' /proc/mounts; then
  fail "Loader partition is already mounted; refusing to disturb another mount."
fi

trap cleanup EXIT
trap 'exit 1' HUP INT TERM
echo 1 >"$INSTALL_FLAG" 2>/dev/null || fail "Cannot set syno_install_flag."
FLAG_SET=1

# Verify that P1 is readable first, then detach and attach a fresh writable
# loop device only for the actual backup copy.
mount -o loop,ro "$LOADER_DISK_PART1" "$WORK_PATH" \
  || fail "Cannot mount ${LOADER_DISK_PART1} read-only."
MOUNTED_BY_US=1
[ -d "$WORK_PATH" ] || fail "P1 mount is not accessible."
umount "$WORK_PATH" || fail "Cannot unmount the read-only P1 check."
MOUNTED_BY_US=0

if is_mounted "$WORK_PATH"; then
  fail "P1 mountpoint became busy before the writable mount."
fi
mount -o loop,rw "$LOADER_DISK_PART1" "$WORK_PATH" \
  || fail "Cannot mount ${LOADER_DISK_PART1} read-write."
MOUNTED_BY_US=1

DEST_DIR="${WORK_PATH}/scbk"
mkdir -p "$DEST_DIR" || fail "Cannot create P1 backup directory."
cp -f "${SCBKPATH}/${FILENAME}" "$DEST_DIR/${FILENAME}" \
  || fail "Cannot copy the configuration backup to P1."
cmp -s "${SCBKPATH}/${FILENAME}" "$DEST_DIR/${FILENAME}" \
  || fail "P1 backup verification failed."

# Keep the existing one-backup-on-P1 behavior, but only prune old files after
# the newly copied backup has been verified.
for old_backup in "$DEST_DIR"/*.dss; do
  [ -e "$old_backup" ] || continue
  [ "$old_backup" = "${DEST_DIR}/${FILENAME}" ] || rm -f -- "$old_backup" \
    || fail "Cannot remove older P1 configuration backups."
done
sync || fail "Failed to flush backup data."
umount "$WORK_PATH" || fail "Cannot unmount P1 after backup."
MOUNTED_BY_US=0

echo 0 >"$INSTALL_FLAG" 2>/dev/null || fail "Cannot reset syno_install_flag."
FLAG_SET=0
trap - EXIT HUP INT TERM
for old_backup in "${SCBKPATH}"/*.dss; do
  [ -e "$old_backup" ] || continue
  [ "$old_backup" = "${SCBKPATH}/${FILENAME}" ] || rm -f -- "$old_backup" \
    || fail "Cannot remove older local configuration backups."
done
echo "Backup copied and verified at ${WORK_PATH}/scbk/${FILENAME}"

exit 0
