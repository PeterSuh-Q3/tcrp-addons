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
[ -f "${FILE_JS}" -a ! -f "${FILE_GZ}" ] && gzip -c "${FILE_JS}" >"${FILE_GZ}"

[ ! -f "${FILE_GZ}" ] && echo "${FILE_GZ} file does not exist" && exit 0

if [ "${1}" = "-r" ]; then
  if [ -f "${FILE_GZ}.bak" ]; then
    mv -f "${FILE_GZ}.bak" "${FILE_GZ}"
    gzip -dc "${FILE_GZ}" >"${FILE_JS}"
  fi
  exit
fi

[ ! -f "${FILE_GZ}.bak" ] && cp -f "${FILE_GZ}" "${FILE_GZ}.bak"

gzip -dc "${FILE_GZ}" >"${FILE_JS}"
sed -i "s/e.portType||e.isCacheTray()/e.portType||false/" "${FILE_JS}"
gzip -c "${FILE_JS}" >"${FILE_GZ}"

xxd -c $(xxd -p "/usr/lib/libhwcontrol.so.1.bak" 2>/dev/null | wc -c) -p "/usr/lib/libhwcontrol.so.1.bak" 2>/dev/null |
  sed "s/0f95c00fb6c0488b9424081000006448/0f94c00fb6c0488b9424081000006448/; s/ffff89c18944240c8b44240809e84409/ffff89c18944240c8b44240890904409/" |
  xxd -r -p >"/usr/lib/libhwcontrol.so.1" 2>/dev/null
  
exit 0
