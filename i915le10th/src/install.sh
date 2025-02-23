#!/bin/sh

set -o pipefail 

PLATFORM="$(uname -u | cut -d '_' -f2)"

function fixintelgpu() {
  # Intel GPU
  echo "replace intel gpu info for i915le10th"

  GPU="$(lspci -nd ::300 2>/dev/null | grep 8086 | cut -d' ' -f3 | sed 's/://g')"
  grep -iq "${GPU}" "/usr/sbin/i915ids" 2>/dev/null || GPU=""
  if [ -z "${GPU}" ] || [ $(echo -n "${GPU}" | wc -c) -ne 8 ]; then
    echo "GPU is not detected"
    exit 0
  fi

  KO_FILE="/usr/lib/modules/i915.ko"
  if [ ! -f "${KO_FILE}" ]; then
    echo "i915.ko does not exist"
    exit 0
  fi  

  isLoad=0
  if lsmod 2>/dev/null | grep -q "^i915"; then
    isLoad=1
    echo "removing i915 ..." 
    /usr/sbin/modprobe -r i915
  fi
  GPU_DEF="86800000923e0000"
  GPU_BIN="${GPU:2:2}${GPU:0:2}0000${GPU:6:2}${GPU:4:2}0000"
  echo "GPU:${GPU} GPU_BIN:${GPU_BIN}"
  cp -pf "${KO_FILE}" "${KO_FILE}.tmp"
  if xxd -c $(xxd -p "${KO_FILE}.tmp" 2>/dev/null | wc -c) -p "${KO_FILE}.tmp" 2>/dev/null |
    sed "s/${GPU_DEF}/${GPU_BIN}/; s/308201f706092a86.*70656e6465647e0a//" |
    xxd -r -p >"${KO_FILE}" 2>/dev/null; then
    echo "i915 xxd proc success!!!" 
  else  
    echo "i915 xxd proc fail!!!" 
  fi  
  rm -vf "${KO_FILE}.tmp"
  if [ "${isLoad}" = "1" ]; then
    echo "doing modprobe i915 ..." 
    /usr/sbin/modprobe i915
  fi
  
}

function copyintelgpu() {
  KO_FILE="/tmpRoot/usr/lib/modules/i915.ko"
  [ ! -f "${KO_FILE}.bak" ] && cp -vf "${KO_FILE}" "${KO_FILE}.bak"
  cp -vf "/usr/lib/modules/i915.ko" "${KO_FILE}"
}

if [ "${1}" = "patches" ]; then
    echo "Installing addon i915le1th - ${1}"

    cp -vf /exts/misc/xxd /usr/bin/xxd
    chmod +x /usr/bin/xxd

    cp -vf /exts/misc/sed /usr/bin/sed
    chmod +x /usr/bin/sed

    cp -vf /exts/misc/i915ids /usr/sbin/i915ids
    chmod +x /usr/sbin/i915ids

    case "${PLATFORM}" in
    apollolake)
        fixintelgpu
        ;;
    geminilake)
        fixintelgpu
        ;;
    esac
    
elif [ "${1}" = "late" ]; then
    echo "Installing addon i915le1th - ${1}"

    case "${PLATFORM}" in
    apollolake)
        copyintelgpu
        ;;
    geminilake)
        copyintelgpu
        ;;
    esac
    
fi
