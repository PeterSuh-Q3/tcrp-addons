#!/usr/bin/env ash

tmpRoot="/tmpRoot"
libPath="/exts/nvmevolume-onthefly"
file="/libhwcontrol.so.1"
PLATFORM="$(uname -u | cut -d '_' -f2)"
REVISION="$(uname -a | cut -d ' ' -f4)"

function prepare_nvme() {
  
  echo "PLATFORM = ${PLATFORM}"
  echo "REVISION = ${REVISION}"

  if [ $(uname -a | grep '4.4.302+' | wc -l) -gt 0 ]; then
    nvmefile="${libPath}/libhwcontrol.so.7.2.${PLATFORM}.tgz"
  elif [ $(uname -a | grep '4.4.180+' | wc -l) -gt 0 ]; then
    nvmefile="${libPath}/libhwcontrol.so.7.1.${PLATFORM}.tgz"
  fi

  echo "nvmefile = ${nvmefile}"
  
  tar xvfz ${nvmefile} -C /etc/

}

function run_modules() {
  prepare_nvme
}

function run_late() {

  echo "Check xxd and libhwcontrol.so.1 file in tmpRoot"
  ls -l ${tmpRoot}/lib64/libhwcontrol.so.1
  ls -l ${tmpRoot}/lib64/libhwcontrol.so
  ls -l ${tmpRoot}/usr/bin/xxd

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
