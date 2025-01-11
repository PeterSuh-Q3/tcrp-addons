#!/usr/bin/env bash
#
# Copyright (C) 2022 Ing <https://github.com/wjz304>
#
# This is free software, licensed under the MIT License.
# See /LICENSE for more information.
#

_BUILD="$(/bin/get_key_value /etc.defaults/VERSION buildnumber)"

if [ ${_BUILD:-64570} -gt 64570 ]; then
  FILE_JS="/usr/local/packages/@appstore/StorageManager/ui/storage_panel.js"
else
  FILE_JS="/usr/syno/synoman/webman/modules/StorageManager/storage_panel.js"
fi
FILE_GZ="${FILE_JS}.gz"
if [ -f "${FILE_JS}" ] && [ ! -f "${FILE_GZ}" ]; then
  gzip -c "${FILE_JS}" >"${FILE_GZ}"
fi

if [ ! -f "${FILE_GZ}" ]; then
  echo "${FILE_GZ} file does not exist"
  exit 0
fi

if [ "${1}" = "-r" ]; then
  if [ -f "${FILE_GZ}.bak" ]; then
    mv -f "${FILE_GZ}.bak" "${FILE_GZ}"
    gzip -dc "${FILE_GZ}" >"${FILE_JS}"
  fi
  exit
fi

[ ! -f "${FILE_GZ}.bak" ] && cp -pf "${FILE_GZ}" "${FILE_GZ}.bak"

gzip -dc "${FILE_GZ}" >"${FILE_JS}"
sed -i "s/e.portType||e.isCacheTray()/e.portType||false/" "${FILE_JS}"
sed -i 's/notSupportM2Pool_addOnCard:this.T("disk_info","disk_reason_m2_add_on_card"),//g' "${FILE_JS}"
sed -i 's/},{isConditionInvalid:0<this.pciSlot,invalidReason:"notSupportM2Pool_addOnCard"//g' "${FILE_JS}"
gzip -c "${FILE_JS}" >"${FILE_GZ}"

exit 0
