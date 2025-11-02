#!/usr/bin/env sh
#
# Copyright (C) 2022 Ing <https://github.com/wjz304>
#
# This is free software, licensed under the MIT License.
# See /LICENSE for more information.
#

KVER_CLEAN=$(uname -r | sed -n 's/^\([0-9]\+\.[0-9]\+\.[0-9]\+\).*/\1/p')
ZPADKVER=$(printf "%01d%03d%03d\n" $(echo "$KVER_CLEAN" | tr '.' ' '))

if [ "${1}" = "late" ]; then
  echo "Installing addon synoconfbkp - ${1}"

  if [ "$ZPADKVER" -le 4004059 ]; then
    echo "(Not Supported) synoconfbkp - ${1}, It does not work on kernel versions 4.4.59 and earlier." 
    exit 0
  fi  

  cp -vpf ./synoconfbkp.sh /tmpRoot/usr/sbin/synoconfbkp.sh
  chmod 755 /tmpRoot/usr/sbin/synoconfbkp.sh
  
  export LD_LIBRARY_PATH=/tmpRoot/sbin:/tmpRoot/lib
  ESYNOSCHEDULER_DB="/tmpRoot/usr/syno/etc/esynoscheduler/esynoscheduler.db"
  echo "insert synoconfbkp task to esynoscheduler.db"
  /tmpRoot/bin/sqlite3 "${ESYNOSCHEDULER_DB}" <<EOF
DELETE FROM task WHERE task_name LIKE 'SynoconfbkpBootup';
INSERT INTO task VALUES('SynoconfbkpBootup', '', 'bootup', '', 1, 0, 0, 0, '', 0, "/usr/sbin/synoconfbkp.sh ${2:-7} ${3:-bkp}_bootup", 'script', '{}', '', '', '{}', '{}');
DELETE FROM task WHERE task_name LIKE 'SynoconfbkpShutdown';
INSERT INTO task VALUES('SynoconfbkpShutdown', '', 'shutdown', '', 1, 0, 0, 0, '', 0, "/usr/sbin/synoconfbkp.sh ${2:-7} ${3:-bkp}_shutdown", 'script', '{}', '', '', '{}', '{}');
EOF
fi
