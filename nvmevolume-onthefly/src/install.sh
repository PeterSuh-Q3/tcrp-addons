#!/usr/bin/env ash

if [ -d "/exts/nvmesystem" ]; then
  echo "nvmevolume is not required if nvmesystem exists!, Skip process!"
  exit 0
fi

# | status      | Hexa value                    |
# | original    | 803e 00b8 0100 0000 7524 488b |
# | patched     | 803e 00b8 0100 0000 9090 488b |

MODEL=$(cat /proc/sys/kernel/syno_hw_version)
tmpRoot="/tmpRoot"
file="/lib64/libhwcontrol.so.1"

if [ "${1}" = "late" ]; then
  echo "nvmevolume-onthefly - ${1}"
  if [ "${MODEL}" = "DS3622xs+" ]; then
    echo "nvmevolume-onthefly - ${1}, Skip DS3622xs+ (Not Supported)"
    exit 0
  fi
  [ ! -f "${tmpRoot}${file}.bak" ] && cp -vf "${tmpRoot}${file}" "${tmpRoot}${file}.bak"
  ${tmpRoot}/usr/bin/xxd -c $(${tmpRoot}/usr/bin/xxd -p "${tmpRoot}${file}.bak" | wc -c) -p "${tmpRoot}${file}.bak" | sed "s/803e00b8010000007524488b/803e00b8010000009090488b/" | ${tmpRoot}/usr/bin/xxd -r -p > "${tmpRoot}${file}"
fi
