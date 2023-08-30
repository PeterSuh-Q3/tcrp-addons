#!/usr/bin/env ash

if [ "${1}" = "late" ]; then
  echo "Installing daemon for i915le10th"

  cp -vf ./i915ids /usr/sbin/i915ids
  chmod +x /usr/sbin/i915ids

  SED_PATH='/tmpRoot/usr/bin/sed'
  XXD_PATH='/tmpRoot/usr/bin/xxd'
  LSPCI_PATH='/tmpRoot/usr/bin/lspci'

  # Intel GPU
  if [ -f /tmpRoot/usr/lib/modules-load.d/70-video-kernel.conf ] && [ -f /tmpRoot/usr/lib/modules/i915.ko ]; then
    export LD_LIBRARY_PATH=/tmpRoot/usr/bin:/tmpRoot/usr/lib:${LD_LIBRARY_PATH}
    GPU="$(${LSPCI_PATH} -n | grep 0300 | grep 8086 | cut -d " " -f 3 | ${SED_PATH} -e 's/://g')"
    echo "${GPU}" >/tmpRoot/root/i915.GPU
    if [ -n "${GPU}" -a $(echo -n "${GPU}" | wc -c) -eq 8 ]; then
      if [ $(grep -i ${GPU} /usr/sbin/i915ids | wc -l) -eq 0 ]; then
        echo "Intel GPU is not detected (${GPU}), nothing to do"
        #${SED_PATH} -i 's/^i915/# i915/g' /tmpRoot/usr/lib/modules-load.d/70-video-kernel.conf
      else
        GPU_DEF="86800000923e0000"
        GPU_BIN="${GPU:2:2}${GPU:0:2}0000${GPU:6:2}${GPU:4:2}0000"
        KO_SIZE="$(${XXD_PATH} -p /tmpRoot/usr/lib/modules/i915.ko | wc -c)"
        ${XXD_PATH} -c ${KO_SIZE} -p /tmpRoot/usr/lib/modules/i915.ko /tmpRoot/root/i915.ko.hex
        if [ $(grep -i "${GPU_BIN}" /tmpRoot/root/i915.ko.hex | wc -l) -gt 0 ]; then
          echo "Intel GPU is detected (${GPU}), already support"
        else
          echo "Intel GPU is detected (${GPU}), replace id"
          if [ ! -f /tmpRoot/usr/lib/modules/i915.ko.bak ]; then
            cp -f /tmpRoot/usr/lib/modules/i915.ko /tmpRoot/usr/lib/modules/i915.ko.bak
          fi
          ${SED_PATH} -i "s/${GPU_DEF}/${GPU_BIN}/; s/308201f706092a86.*70656e6465647e0a//" /tmpRoot/root/i915.ko.hex
          if [ -n "$(cat /tmpRoot/root/i915.ko.hex)" ]; then
            ${XXD_PATH} -r -p /tmpRoot/root/i915.ko.hex >/tmpRoot/usr/lib/modules/i915.ko
            rm -f /tmpRoot/root/i915.ko.hex

            rmmod i915
            insmod /tmpRoot/usr/lib/modules/i915.ko
          else
            echo "Intel GPU is detected (${GPU}), replace i915.ko error"
          fi
        fi
      fi
    fi
  fi
fi
