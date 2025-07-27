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
#  (row)X(column)

HDD_BAY_LIST=(RACK_0_Bay RACK_2_Bay RACK_4_Bay RACK_8_Bay RACK_10_Bay RACK_12_Bay RACK_12_Bay_2 RACK_16_Bay RACK_20_Bay RACK_24_Bay RACK_60_Bay
  TOWER_1_Bay TOWER_2_Bay TOWER_4_Bay TOWER_4_Bay_J TOWER_4_Bay_S TOWER_5_Bay TOWER_6_Bay TOWER_8_Bay TOWER_12_Bay)

if [ "${1}" = "-h" ]; then
  echo "Use: ${0} [HDD_BAY [SSD_BAY]]"
  echo "  HDD_BAY: ${HDD_BAY_LIST[*]}"
  echo "  SSD_BAY: (row)X(column)"
  echo "  -r: restore"
  echo "  -h: help"
  echo "  e.g.:"
  echo "    ${0}                  - auto"
  echo "    ${0} RACK_24_Bay      - HDD_BAY set to RACK_24_Bay, SSD_BAY auto"
  echo "    ${0} RACK_24_Bay 1X8  - HDD_BAY set to RACK_24_Bay, SSD_BAY set to 1X8"
  echo "    ${0} RACK_60_Bay 2X8  - HDD_BAY set to RACK_60_Bay, SSD_BAY set to 2X8"
  echo "    ${0} -r               - restore"
  echo "    ${0} -h               - help"
  exit
fi

_UNIQUE="$(/bin/get_key_value /etc.defaults/synoinfo.conf unique)"
_BUILD="$(/bin/get_key_value /etc.defaults/VERSION buildnumber)"

if [ ${_BUILD:-64570} -gt 64570 ]; then
  FILE_JS="/usr/local/packages/@appstore/StorageManager/ui/storage_panel.js"
else
  FILE_JS="/usr/syno/synoman/webman/modules/StorageManager/storage_panel.js"
fi
FILE_GZ="${FILE_JS}.gz"
[ -f "${FILE_JS}" ] && [ ! -f "${FILE_GZ}" ] && gzip -c "${FILE_JS}" >"${FILE_GZ}"

if [ ! -f "${FILE_GZ}" ]; then
  echo "${FILE_GZ} file does not exist"
  exit 0
fi

if [ "${1}" = "-r" ]; then
  if [ -f "${FILE_GZ}.bak" ]; then
    mv -f "${FILE_GZ}.bak" "${FILE_GZ}"
    gzip -dc "${FILE_GZ}" >"${FILE_JS}"
  fi
  SM_KEY="sm_machine_img_config_name"
  synosetkeyvalue "/etc.defaults/synoinfo.conf" "${SM_KEY}" "$(synogetkeyvalue /etc/synoinfo.conf "${SM_KEY}")"
  exit
fi

[ -n "${1}" ] && HDD_BAY="$(echo "${HDD_BAY_LIST[@]}" | grep -iwo "${1}")" || HDD_BAY=""
if [ -n "${1}" ] && [ -z "${HDD_BAY}" ]; then
  echo "parameter 1 error"
fi

SSD_BAY="$(echo "${2^^}" | sed 's/*/X/')"
if [ -n "${SSD_BAY}" ] && [ -z "$(echo "${SSD_BAY}" | sed -n '/^[0-9]\{1,2\}X[0-9]\{1,2\}$/p')" ]; then
  echo "parameter 2 error"
  SSD_BAY=""
fi

if [ -z "${HDD_BAY}" ]; then
  if [ -f "/run/model.dtb" ]; then # if [ ! "$(/bin/get_key_value /etc/synoinfo.conf supportportmappingv2)" = "yes" ]; then
    IDX="$(grep -ao "internal_slot@" "/run/model.dtb" | wc -w)"
  else
    IDX="$(synodisk --enum -t internal 2>/dev/null | grep "Disk id:" | cut -d: -f2 | sort -n | tail -n1 | xargs)"
  fi
  while [ ${IDX:-0} -le 60 ]; do
    for i in "${HDD_BAY_LIST[@]}"; do
      echo "${i}" | grep -q "_${IDX:-0}_" && HDD_BAY="${i}" && break 2
    done
    IDX=$((${IDX:-0} + 1))
  done
  HDD_BAY=${HDD_BAY:-RACK_60_Bay}
fi

if [ -z "${SSD_BAY}" ]; then
  if [ -f "/run/model.dtb" ]; then # if [ ! "$(/bin/get_key_value /etc/synoinfo.conf supportportmappingv2)" = "yes" ]; then
    IDX="$(grep -ao "nvme_slot@" "/run/model.dtb" | wc -w)"
  else
    IDX="$(synodisk --enum -t cache 2>/dev/null | grep "Disk id:" | cut -d: -f2 | sort -n | tail -n1 | xargs)"
  fi
  [ "${IDX:-0}" -le 8 ] && SSD_BAY="1X${IDX:-0}" || SSD_BAY="$((${IDX:-0} / 8 + 1))X8"
fi

[ ! -f "${FILE_GZ}.bak" ] && cp -pf "${FILE_GZ}" "${FILE_GZ}.bak"

gzip -dc "${FILE_GZ}.bak" >"${FILE_JS}"

echo "storagepanel set to ${HDD_BAY} ${SSD_BAY}"
OLD="driveShape:\"Mdot2-shape\",major:\"row\",rowDir:\"UD\",colDir:\"LR\",driveSection:\[{top:14,left:18,rowCnt:[0-9]\+,colCnt:[0-9]\+,xGap:6,yGap:6}\]},"
NEW="driveShape:\"Mdot2-shape\",major:\"row\",rowDir:\"UD\",colDir:\"LR\",driveSection:\[{top:14,left:18,rowCnt:${SSD_BAY%%X*},colCnt:${SSD_BAY##*X},xGap:6,yGap:6}\]},"
sed -i "s/\"${_UNIQUE}\",//g; s/,\"${_UNIQUE}\"//g; s/${HDD_BAY}:\[\"/${HDD_BAY}:\[\"${_UNIQUE}\",\"/g; s/M2X1:\[\"/M2X1:\[\"${_UNIQUE}\",\"/g; s/${OLD}/${NEW}/g" "${FILE_JS}"
if [ -f "/usr/lib/systemd/system/tad6s4n10g.service" ]; then
  sed -i 's|major:"row",rowDir:"UD",colDir:"LR",driveSection:\[{top:22,left:26,rowCnt:1,colCnt:6,|major:"row",rowDir:"DU",colDir:"RL",driveSection:\[{top:22,left:26,rowCnt:1,colCnt:6,|g' "${FILE_JS}"
  sed -i 's|major:"row",rowDir:"UD",colDir:"LR",driveSection:\[{top:22,left:26,rowCnt:1,colCnt:8,|major:"row",rowDir:"DU",colDir:"RL",driveSection:\[{top:22,left:26,rowCnt:1,colCnt:8,|g' "${FILE_JS}"
fi
if [ -f "/usr/lib/systemd/system/nvmesystem.service" ] || [ -f "/usr/lib/systemd/system/nvmevolume.service" ]; then
  # 64570
  sed -i "s/e.portType||e.isCacheTray()/e.portType||false/g" "${FILE_JS}"                                    # [42962,?)
  sed -i 's/("normal"!==this.portType)/("normal"!==this.portType\&\&"cache"!==this.portType)/g' "${FILE_JS}" # [64570,?)
  # 42218
  sed -i "s/\!u.isCacheTray()/(\!u.isCacheTray()||true)/g" "${FILE_JS}"                                            # [42218,42962)
  sed -i 's/t="normal"!==this.portType/t="normal"!==this.portType\&\&"cache"!==this.portType/g' "${FILE_JS}"       # [42218,64570)
  sed -i 's/return"normal"===this.portType/return"normal"===this.portType||"cache"===this.portType/g' "${FILE_JS}" # [42218,64570)
fi
gzip -c "${FILE_JS}" >"${FILE_GZ}"

SM_KEY="sm_machine_img_config_name"
synosetkeyvalue "/etc.defaults/synoinfo.conf" "${SM_KEY}" "" # "${HDD_BAY}-M2X1"

exit 0
