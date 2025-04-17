#!/usr/bin/env sh
#
# Copyright (C) 2022 Ing <https://github.com/wjz304>
#
# This is free software, licensed under the MIT License.
# See /LICENSE for more information.
#

if [ "${1}" = "late" ]; then
  echo "Installing addon synoconfbkp - ${1}"
  mkdir -p "/tmpRoot/usr/rr/addons/"
  cp -pf "${0}" "/tmpRoot/usr/rr/addons/"

  cp -vpf /usr/bin/rr-synoconfbkp.sh /tmpRoot/usr/bin/rr-synoconfbkp.sh
  
  export LD_LIBRARY_PATH=/tmpRoot/bin:/tmpRoot/lib
  ESYNOSCHEDULER_DB="/tmpRoot/usr/syno/etc/esynoscheduler/esynoscheduler.db"
  if [ ! -f "${ESYNOSCHEDULER_DB}" ] || ! /tmpRoot/bin/sqlite3 "${ESYNOSCHEDULER_DB}" ".tables" | grep -qw "task"; then
    echo "copy esynoscheduler.db"
    mkdir -p "$(dirname "${ESYNOSCHEDULER_DB}")"
    cp -vpf /addons/esynoscheduler.db "${ESYNOSCHEDULER_DB}"
  fi
  echo "insert synoconfbkp task to esynoscheduler.db"
  /tmpRoot/bin/sqlite3 "${ESYNOSCHEDULER_DB}" <<EOF
DELETE FROM task WHERE task_name LIKE 'SynoconfbkpBootup';
INSERT INTO task VALUES('SynoconfbkpBootup', '', 'bootup', '', 1, 0, 0, 0, '', 0, "/usr/bin/rr-synoconfbkp.sh ${2:-7} ${3:-bkp}_bootup", 'script', '{}', '', '', '{}', '{}');
DELETE FROM task WHERE task_name LIKE 'SynoconfbkpShutdown';
INSERT INTO task VALUES('SynoconfbkpShutdown', '', 'shutdown', '', 1, 0, 0, 0, '', 0, "/usr/bin/rr-synoconfbkp.sh ${2:-7} ${3:-bkp}_shutdown", 'script', '{}', '', '', '{}', '{}');
EOF
elif [ "${1}" = "uninstall" ]; then
  echo "Installing addon synoconfbkp - ${1}"

  rm -f "/tmpRoot/usr/bin/rr-synoconfbkp.sh"

  export LD_LIBRARY_PATH=/tmpRoot/bin:/tmpRoot/lib
  ESYNOSCHEDULER_DB="/tmpRoot/usr/syno/etc/esynoscheduler/esynoscheduler.db"
  if [ -f "${ESYNOSCHEDULER_DB}" ]; then
    echo "delete synoconfbkp task from esynoscheduler.db"
    /tmpRoot/bin/sqlite3 "${ESYNOSCHEDULER_DB}" <<EOF
DELETE FROM task WHERE task_name LIKE 'SynoconfbkpBootup';
DELETE FROM task WHERE task_name LIKE 'SynoconfbkpShutdown';
EOF
  fi
fi
