#!/usr/bin/env ash

if [ -d "/exts/nvmesystem" ]; then
  echo "nvmevolume is not required if nvmesystem exists!, Skip process!"
  exit 0
fi

# | status      | Hexa value                    |
# | original    | 803e 00b8 0100 0000 7520 488b | 7.1.X
# | original    | 803e 00b8 0100 0000 7524 488b | 7.2.X
# | patched     | 803e 00b8 0100 0000 9090 488b |

PLATFORM="$(uname -a | awk '{print $NF}' | cut -d '_' -f2)"
tmpRoot="/tmpRoot"
file="/lib64/libhwcontrol.so.1"

if [ "${1}" = "late" ]; then
  echo "nvmevolume-onthefly - ${1}"
  if [ "${PLATFORM}" = "broadwellnk" ] || [ "${PLATFORM}" = "bromolow" ]; then
    echo "nvmevolume-onthefly - ${1}, Skip ${PLATFORM} (Not Supported)"
    exit 0
  fi

  REVISION="$(uname -a | cut -d ' ' -f4)"
  echo "REVISION = ${REVISION}"
  if [ ${REVISION} = "#42218" ]; then
    echo "nvmevolume-onthefly - ${1}, Skip ${REVISION} (Not Supported)"
    exit 0
  fi  
    
  [ ! -f "${tmpRoot}${file}.bak" ] && cp -vf "${tmpRoot}${file}" "${tmpRoot}${file}.bak"
  ${tmpRoot}/usr/bin/xxd -c $(${tmpRoot}/usr/bin/xxd -p "${tmpRoot}${file}.bak" | wc -c) -p "${tmpRoot}${file}.bak" | sed "s/803e00b801000000752.488b/803e00b8010000009090488b/" | ${tmpRoot}/usr/bin/xxd -r -p > "${tmpRoot}${file}"
fi
