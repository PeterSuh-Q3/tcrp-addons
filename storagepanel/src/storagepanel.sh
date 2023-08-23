#!/usr/bin/env bash
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
#  RACK_24_Bay
#  RACK_60_Bay       # default
#  TOWER_1_Bay
#  TOWER_2_Bay
#  TOWER_4_Bay
#  TOWER_4_Bay_J
#  TOWER_4_Bay_S
#  TOWER_5_Bay
#  TOWER_6_Bay
#  TOWER_8_Bay
#  TOWER_12_Bay
#  -r
# $2 ?
#  number            # default: 1X8

HDD_BAY="${1:-RACK_24_Bay}"
SSD_BAY="${2:-1X8}"

FILE_JS="/usr/syno/synoman/webman/modules/StorageManager/storage_panel.js"
FILE_GZ="${FILE_JS}.gz"
_UNIQUE=$(/bin/get_key_value /etc.defaults/synoinfo.conf unique)

HDD_BAY_LIST=(RACK_0_Bay RACK_2_Bay RACK_4_Bay RACK_8_Bay RACK_10_Bay RACK_12_Bay RACK_12_Bay_2 RACK_16_Bay RACK_20_Bay RACK_24_Bay RACK_60_Bay
  TOWER_1_Bay TOWER_2_Bay TOWER_4_Bay TOWER_4_Bay_J TOWER_4_Bay_S TOWER_5_Bay TOWER_6_Bay TOWER_8_Bay TOWER_12_Bay)

if [ "${HDD_BAY}" = "-r" ]; then
  if [ -f "${FILE_GZ}.bak" ]; then
    rm -f "${FILE_JS}" "${FILE_GZ}"
    cp -f "${FILE_GZ}.bak" "${FILE_GZ}"
    gzip -dc "${FILE_GZ}" >"${FILE_JS}"
    chmod a+r "${FILE_JS}" "${FILE_GZ}"
  fi
  exit
fi

if ! echo "${HDD_BAY_LIST[@]}" | grep -wq "${HDD_BAY}"; then
  echo "parameter 1 error"
  exit
fi

if [ -z "$(echo ${SSD_BAY} | sed -n '/^[0-9]\{1,2\}X[0-9]\{1,2\}$/p')" ]; then
  echo "parameter 2 error"
  exit
fi

[ ! -f "${FILE_GZ}.bak" ] && cp -f "${FILE_GZ}" "${FILE_GZ}.bak" && chmod a+r "${FILE_GZ}.bak"

rm -f "${FILE_JS}"
gzip -dc "${FILE_GZ}.bak" >"${FILE_JS}"

OLD="driveShape:\"Mdot2-shape\",major:\"row\",rowDir:\"UD\",colDir:\"LR\",driveSection:\[{top:14,left:18,rowCnt:1,colCnt:2,xGap:6,yGap:6}\]},"
NEW="driveShape:\"Mdot2-shape\",major:\"row\",rowDir:\"UD\",colDir:\"LR\",driveSection:\[{top:14,left:18,rowCnt:${SSD_BAY%%X*},colCnt:${SSD_BAY##*X},xGap:6,yGap:6}\]},"
sed -i "s/\"${_UNIQUE}\",//g; s/,\"${_UNIQUE}\"//g; s/${HDD_BAY}:\[\"/${HDD_BAY}:\[\"${_UNIQUE}\",\"/g; s/M2X1:\[\"/M2X1:\[\"${_UNIQUE}\",\"/g; s/${OLD}/${NEW}/g" "${FILE_JS}"

gzip -c "${FILE_JS}" >"${FILE_GZ}"
chmod a+r "${FILE_JS}" "${FILE_GZ}"

exit 0
