#!/usr/bin/env sh
#
# Copyright (C) 2022 Ing <https://github.com/wjz304>
#
# This is free software, licensed under the MIT License.
# See /LICENSE for more information.
#

if [ "${1}" = "late" ]; then
  echo "Installing addon sensors - ${1}"
  mkdir -p "/tmpRoot/usr/mshell/addons/"
  cp -pf "${0}" "/tmpRoot/usr/mshell/addons/"

  tar -zxf ./sensors-7.1.tgz -C /tmpRoot/usr/
  cp -vpf ./rr-sensors.sh /tmpRoot/usr/bin/rr-sensors.sh

  export LD_LIBRARY_PATH=/tmpRoot/bin:/tmpRoot/lib
  ESYNOSCHEDULER_DB="/tmpRoot/usr/syno/etc/esynoscheduler/esynoscheduler.db"
  if [ ! -f "${ESYNOSCHEDULER_DB}" ] || ! /tmpRoot/bin/sqlite3 "${ESYNOSCHEDULER_DB}" ".tables" | grep -wq "task"; then
    echo "copy esynoscheduler.db"
    mkdir -p "$(dirname "${ESYNOSCHEDULER_DB}")"
    cp -vpf ./esynoscheduler.db "${ESYNOSCHEDULER_DB}"
  fi
  if echo "SELECT * FROM task;" | /tmpRoot/bin/sqlite3 "${ESYNOSCHEDULER_DB}" | grep -E "Fancontrol" -A12 | grep -Eq "^FANMODES=(.*)$"; then
    echo "Fancontrol task already exists"
  else
    echo "insert sensors task to esynoscheduler.db"
    /tmpRoot/bin/sqlite3 "${ESYNOSCHEDULER_DB}" <<EOF
DELETE FROM task WHERE task_name LIKE 'Fancontrol';
INSERT INTO task VALUES('Fancontrol', '', 'bootup', '', 0, 0, 0, 0, '', 0, '
# 只需要修改以下12个值即可，无需运行该任务，修改后切换风扇模式生效。
# You only need to modify the following 12 values. You do not need to run the task. After the modification, the fan mode switch will take effect.
# 或者自行创建 /etc/fancontrol.full, /etc/fancontrol.high, /etc/fancontrol.low 文件，内容为 /etc/fancontrol 的内容。
# Or create /etc/fancontrol.full, /etc/fancontrol.high, /etc/fancontrol.low files with the same content as /etc/fancontrol.
#
#            fullfan        coolfan        quietfan
#               |              |              |
FANMODES=("20 40 255 127" "30 60 255 63" "40 80 192 63")
#           ^  ^  ^  ^
#           1  2  3  4
# 1: MINTEMP  2: MAXTEMP  3: MINSTART  4: MINSTOP
', 'script', '{}', '', '', '{}', '{}');
EOF
  fi

  mkdir -p "/tmpRoot/usr/lib/systemd/system"
  DEST="/tmpRoot/usr/lib/systemd/system/sensors.service"
  {
    echo "[Unit]"
    echo "Description=RR addon sensors daemon"
    echo "After=multi-user.target"
    echo "After=scemd.service"
    echo
    echo "[Service]"
    echo "Type=forking"
    echo "ExecStart=/usr/bin/rr-sensors.sh"
    echo "ExecReload=/usr/bin/pkill -f /usr/bin/rr-sensors.sh"
    echo "Restart=always"
    echo "StartLimitBurst=5"
    echo "StartLimitInterval=10"
    echo
    echo "[Install]"
    echo "WantedBy=multi-user.target"
  } >"${DEST}"

  mkdir -vp /tmpRoot/usr/lib/systemd/system/multi-user.target.wants
  ln -vsf /usr/lib/systemd/system/sensors.service /tmpRoot/usr/lib/systemd/system/multi-user.target.wants/sensors.service

elif [ "${1}" = "uninstall" ]; then
  echo "Installing addon sensors - ${1}"

  rm -f "/tmpRoot/usr/lib/systemd/system/multi-user.target.wants/sensors.service"
  rm -f "/tmpRoot/usr/lib/systemd/system/sensors.service"

  rm -f /tmpRoot/etc/fancontrol
  rm -f /tmpRoot/usr/bin/rr-sensors.sh

  export LD_LIBRARY_PATH=/tmpRoot/bin:/tmpRoot/lib
  ESYNOSCHEDULER_DB="/tmpRoot/usr/syno/etc/esynoscheduler/esynoscheduler.db"
  if [ -f "${ESYNOSCHEDULER_DB}" ]; then
    echo "delete sensors task from esynoscheduler.db"
    /tmpRoot/bin/sqlite3 "${ESYNOSCHEDULER_DB}" <<EOF
DELETE FROM task WHERE task_name LIKE 'Fancontrol';
EOF
  fi
fi
