#!/usr/bin/env ash

echo "Installing daemon for i915le10th"

cp -vf ./i915ids /usr/sbin/i915ids
chmod +x /usr/sbin/i915ids

SED_PATH='/usr/bin/sed'
XXD_PATH='/usr/bin/xxd'
LSPCI_PATH='/usr/bin/lspci'

# Intel GPU
if [ -f /usr/lib/modules-load.d/70-video-kernel.conf ] && [ -f /usr/lib/modules/i915.ko ]; then
  export LD_LIBRARY_PATH=/usr/bin:/usr/lib:${LD_LIBRARY_PATH}
  GPU="$(${LSPCI_PATH} -n | grep 0300 | grep 8086 | cut -d " " -f 3 | ${SED_PATH} -e 's/://g')"
  echo "${GPU}" >/root/i915.GPU
  if [ -n "${GPU}" -a $(echo -n "${GPU}" | wc -c) -eq 8 ]; then
    if [ $(grep -i ${GPU} /usr/sbin/i915ids | wc -l) -eq 0 ]; then
      echo "Intel GPU is not detected (${GPU}), nothing to do"
      #${SED_PATH} -i 's/^i915/# i915/g' /usr/lib/modules-load.d/70-video-kernel.conf
    else
      GPU_DEF="86800000923e0000"
      GPU_BIN="${GPU:2:2}${GPU:0:2}0000${GPU:6:2}${GPU:4:2}0000"
      KO_SIZE="$(${XXD_PATH} -p /usr/lib/modules/i915.ko | wc -c)"
      ${XXD_PATH} -c ${KO_SIZE} -p /usr/lib/modules/i915.ko /root/i915.ko.hex
      if [ $(grep -i "${GPU_BIN}" /root/i915.ko.hex | wc -l) -gt 0 ]; then
        echo "Intel GPU is detected (${GPU}), already support"
      else
        echo "Intel GPU is detected (${GPU}), replace id"
        if [ ! -f /usr/lib/modules/i915.ko.bak ]; then
          cp -f /usr/lib/modules/i915.ko /usr/lib/modules/i915.ko.bak
        fi
        ${SED_PATH} -i "s/${GPU_DEF}/${GPU_BIN}/; s/308201f706092a86.*70656e6465647e0a//" /root/i915.ko.hex
        if [ -n "$(cat /root/i915.ko.hex)" ]; then
          ${XXD_PATH} -r -p /root/i915.ko.hex >/usr/lib/modules/i915.ko
          rm -f /root/i915.ko.hex

          rmmod i915
          insmod /usr/lib/modules/i915.ko
        else
          echo "Intel GPU is detected (${GPU}), replace i915.ko error"
        fi
      fi
    fi
  fi
fi
