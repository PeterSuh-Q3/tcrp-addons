#!/usr/bin/env ash
#
# Copyright (C) 2022 Ing <https://github.com/wjz304>
#
# This is free software, licensed under the MIT License.
# See /LICENSE for more information.
#
# $1 ?
#  RACK_0_Bay
#  RACK_2_Bay
#  RACK_4_Bay
#  RACK_8_Bay
#  RACK_10_Bay
#  RACK_12_Bay
#  RACK_12_Bay_2
#  RACK_16_Bay
#  RACK_20_Bay
#  RACK_24_Bay       # default
#  RACK_60_Bay
#  TOWER_1_Bay
#  TOWER_2_Bay
#  TOWER_4_Bay
#  TOWER_4_Bay_J
#  TOWER_4_Bay_S
#  TOWER_5_Bay
#  TOWER_6_Bay
#  TOWER_8_Bay
#  TOWER_12_Bay
#  -r                # restore
# $2 ?
#  (row)X(column)    # default: 1X8

if [ "${1}" = "late" ]; then

HDD_BAY="RACK_60_Bay"
SSD_BAY="1X4"

_UNIQUE="$(/bin/get_key_value /etc.defaults/synoinfo.conf unique)"
_BUILD="$(/bin/get_key_value /etc.defaults/VERSION buildnumber)"

if [ ${_BUILD:-64570} -gt 64570 ]; then
  FILE_JS="/usr/local/packages/@appstore/StorageManager/ui/storage_panel.js"
else
  FILE_JS="/usr/syno/synoman/webman/modules/StorageManager/storage_panel.js"
fi
FILE_GZ="${FILE_JS}.gz"
[ -f "${FILE_JS}" -a ! -f "${FILE_GZ}" ] && gzip -c "${FILE_JS}" >"${FILE_GZ}"

[ ! -f "${FILE_GZ}" ] && echo "${FILE_GZ} file does not exist" && exit 0

HDD_BAY_LIST="RACK_0_Bay RACK_2_Bay RACK_4_Bay RACK_8_Bay RACK_10_Bay RACK_12_Bay RACK_12_Bay_2 RACK_16_Bay RACK_20_Bay RACK_24_Bay RACK_60_Bay TOWER_1_Bay TOWER_2_Bay TOWER_4_Bay TOWER_4_Bay_J TOWER_4_Bay_S TOWER_5_Bay TOWER_6_Bay TOWER_8_Bay TOWER_12_Bay"

if [ "${HDD_BAY}" = "-r" ]; then
  if [ -f "${FILE_GZ}.bak" ]; then
    mv -f "${FILE_GZ}.bak" "${FILE_GZ}"
    gzip -dc "${FILE_GZ}" >"${FILE_JS}"
  fi
fi

[ ! -f "${FILE_GZ}.bak" ] && cp -f "${FILE_GZ}" "${FILE_GZ}.bak"

gzip -dc "${FILE_GZ}" >"${FILE_JS}"
echo "storagepanel set to ${HDD_BAY} ${SSD_BAY}"
OLD="driveShape:\"Mdot2-shape\",major:\"row\",rowDir:\"UD\",colDir:\"LR\",driveSection:\[{top:14,left:18,rowCnt:[0-9]\+,colCnt:[0-9]\+,xGap:6,yGap:6}\]},"
NEW="driveShape:\"Mdot2-shape\",major:\"row\",rowDir:\"UD\",colDir:\"LR\",driveSection:\[{top:14,left:18,rowCnt:${SSD_BAY%%X*},colCnt:${SSD_BAY##*X},xGap:6,yGap:6}\]},"
sed -i "s/\"${_UNIQUE}\",//g; s/,\"${_UNIQUE}\"//g; s/${HDD_BAY}:\[\"/${HDD_BAY}:\[\"${_UNIQUE}\",\"/g; s/M2X1:\[\"/M2X1:\[\"${_UNIQUE}\",\"/g; s/${OLD}/${NEW}/g" "${FILE_JS}"
gzip -c "${FILE_JS}" >"${FILE_GZ}"

  echo "Installing manual schedule for storagepanel"
  cp -v ./storagepanel.sh /tmpRoot/usr/sbin/storagepanel.sh
  chmod +x /tmpRoot/usr/sbin/storagepanel.sh
  if [ -f /tmpRoot/usr/syno/etc/esynoscheduler/esynoscheduler.db ]; then
    if [ $(/tmpRoot/bin/sqlite3 /tmpRoot/usr/syno/etc/esynoscheduler/esynoscheduler.db "select count(*) as cnt from task a where task_name = 'Change Storage Panel';") -gt "0" ]; then
      echo "A Change Storage Panel task already exists at task_name. skipped!!!"
    else
      echo "insert Change Storage Panel task"
      /tmpRoot/bin/sqlite3 /tmpRoot/usr/syno/etc/esynoscheduler/esynoscheduler.db "INSERT INTO task VALUES('Change Storage Panel', '', '-', '', 0, 0, 0, 0, '', 0, '/usr/sbin/storagepanel.sh RACK_60_Bay 1X2 # RACK_0_Bay RACK_2_Bay RACK_4_Bay RACK_8_Bay RACK_10_Bay RACK_12_Bay RACK_12_Bay_2 RACK_16_Bay RACK_20_Bay RACK_24_Bay RACK_60_Bay TOWER_1_Bay TOWER_2_Bay TOWER_4_Bay TOWER_4_Bay_J TOWER_4_Bay_S TOWER_5_Bay TOWER_6_Bay TOWER_8_Bay TOWER_12_Bay', 'script', '{}', '', '', '{}', '{}');"
    fi
  fi
  
  exit 0

fi
