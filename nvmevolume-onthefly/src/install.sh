#!/usr/bin/env ash

# | status      | Hexa value                    |
# | original    | 803e 00b8 0100 0000 7524 488b |
# | patched     | 803e 00b8 0100 0000 9090 488b |

tmpRoot="/tmpRoot"
file="/lib64/libhwcontrol.so.1"

if [ "${1}" = "late" ]; then
  echo "nvmevolume-onthefly - ${1}"
  [ ! -f "${tmpRoot}${file}.bak" ] && cp -vf "${tmpRoot}${file}" "${tmpRoot}${file}.bak"
  sed -i "s/803e00b8010000007524488b/803e00b8010000009090488b/" "${tmpRoot}${file}"
fi
