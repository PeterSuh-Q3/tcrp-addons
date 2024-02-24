#!/usr/bin/env ash

# | status      | Hexa value                    |
# | original    | 803e 00b8 0100 0000 7524 488b |
# | patched     | 803e 00b8 0100 0000 9090 488b |

# caution : In the case of ApolloLake, hexa detection is impossible if octets per line is specified as 256 bytes. It should be adjusted to 200.
# xxd -c cols     format <cols> octets per line. Default 16 Max 256 (-i: 12, -ps: 30)

tmpRoot="/tmpRoot"
file="/lib64/libhwcontrol.so.1"
PLATFORM="$(uname -u | cut -d '_' -f2)"

echo "nvmevolume-onthefly - PLATFORM = ${PLATFORM}"

if [ ${PLATFORM} = "apollolake" ]; then
  cols="200"
else
  cols="256"
fi  

if [ "${1}" = "late" ]; then
  echo "nvmevolume-onthefly - ${1}"
  cp -vf ${tmpRoot}${file} ${tmpRoot}${file}.bak
  ${tmpRoot}/usr/bin/xxd -c ${cols} ${tmpRoot}${file}.bak | sed "s/803e 00b8 0100 0000 7524 488b/803e 00b8 0100 0000 9090 488b/" | xxd -c ${cols} -r > ${tmpRoot}${file}
fi
