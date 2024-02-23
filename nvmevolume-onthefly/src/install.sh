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

function run_modules() {
  prepare_nvme
}

function run_late() {
  echo "nvme-cache - late"
  echo "Copy libhwcontrol.so.1 file to tmpRoot"
  cp -vf /etc/libhwcontrol.so.1 ${tmpRoot}/lib64/
  #ln -s ${tmpRoot}/lib64/libhwcontrol.so.1 ${tmpRoot}/lib64/libhwcontrol.so
}

if [ "${1}" = "modules" ]; then
  echo "nvme-cache - ${1}"
  run_modules
elif [ "${1}" = "late" ]; then
  echo "nvme-cache - ${1}"
  run_late
fi
