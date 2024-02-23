#!/usr/bin/env ash

tmpRoot="/tmpRoot"
libPath="/exts/nvmevolume-onthefly"
file="/libhwcontrol.so.1"

function prepare_nvme() {

  REVISION="$(uname -a | cut -d ' ' -f4)"
  echo "REVISION = ${REVISION}"

  if [ $(uname -a | grep '4.4.302+' | wc -l) -gt 0 ]; then
    nvmefile="${libPath}/libhwcontrol.so.7.2"
  elif [ $(uname -a | grep '4.4.180+' | wc -l) -gt 0 ]; then
    if [ ${REVISION} = "#42218" ]; then
      nvmefile="${libPath}/libhwcontrol.so.7.0"
    else
      nvmefile="${libPath}/libhwcontrol.so.7.1"
    fi
  fi

  echo "nvmefile = ${nvmefile}"
  
  cp -vf ${nvmefile} /etc${file}

}

function modify_synoinfo() {

# Enable creating M.2 storage pool and volume in Storage Manager
# for currently installed NVMe drives
    for nvme in /run/synostorage/disks/nvme*; do
        if [[ -f /run/synostorage/disks/"$(basename -- "$1")"/m2_pool_support ]]; then
            echo 1 > /run/synostorage/disks/"$(basename -- "$nvme")"/m2_pool_support
        fi
    done

}

function run_modules() {
  echo "nvme-cache - modules"
  prepare_nvme
}

function run_late() {
  echo "nvme-cache - late"
  echo "Copy libhwcontrol.so.1 file to tmpRoot"
  cp -vf /etc/libhwcontrol.so.1 ${tmpRoot}/lib64/
  ln ${tmpRoot}/lib64/libhwcontrol.so.1 ${tmpRoot}/lib64/libhwcontrol.so
 #modify_synoinfo
}

if [ "${1}" = "modules" ]; then
  run_modules
elif [ "${1}" = "patches" ]; then
  echo "nvme-cache - patches"
  tmpRoot=""
  run_late
elif [ "${1}" = "late" ]; then
  run_late
fi
