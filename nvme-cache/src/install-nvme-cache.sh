#!/bin/bash

if [ $# -lt 1 ]; then
  tmpRoot=""
  libPath="/lib64"
  dsmMode="ON"
else
  tmpRoot="/tmpRoot"
  libPath="."
  dsmMode="OFF"
fi

function prepare_nvme() {

  echo "Collecting 1st nvme paths"
  nvmepath1=$(/usr/sbin/readlink /sys/class/nvme/nvme0 | sed 's|^.*\(pci.*\)|\1|' | cut -d'/' -f2- | cut -d'/' -f1)
  echo "Found local 1st nvme with path $nvmepath1"
  if [ $(echo $nvmepath1 | wc -w) -eq 0 ]; then
      echo "Not found local 1st nvme"
      exit 0
  else
      hex1=$(/usr/sbin/readlink /sys/class/nvme/nvme0 | sed 's|^.*\(pci.*\)|\1|' | cut -d'/' -f2- | cut -d'/' -f1 | cut -d':' -f3 | cut -c 1-1 | xxd  -c 256 -ps | sed "s/..$//")
      hex2=$(/usr/sbin/readlink /sys/class/nvme/nvme0 | sed 's|^.*\(pci.*\)|\1|' | cut -d'/' -f2- | cut -d'/' -f1 | cut -d':' -f3 | cut -c 2-2 | xxd  -c 256 -ps | sed "s/..$//")
      hex3=$(/usr/sbin/readlink /sys/class/nvme/nvme0 | sed 's|^.*\(pci.*\)|\1|' | cut -d'/' -f2- | cut -d'/' -f1 | cut -d':' -f3 | cut -c 4-4 | xxd  -c 256 -ps | sed "s/..$//")
      nvme1hex=$(echo "3a$hex1 $hex2/2e $hex3/00" | sed "s/\///g" )
      echo $nvme1hex

      nvme3hex=$(echo "$hex1$hex2 2e$hex3")
      echo $nvme3hex
  fi

  echo ""
  echo "Collecting 2nd nvme paths"
  nvmepath2=$(/usr/sbin/readlink /sys/class/nvme/nvme1 | sed 's|^.*\(pci.*\)|\1|' | cut -d'/' -f2- | cut -d'/' -f1)
  echo "Found local 2nd nvme with path $nvmepath2"
  if [ $(echo $nvmepath2 | wc -w) -eq 0 ]; then
      echo "Not found local 2nd nvme"
  else
      hex4=$(/usr/sbin/readlink /sys/class/nvme/nvme1 | sed 's|^.*\(pci.*\)|\1|' | cut -d'/' -f2- | cut -d'/' -f1 | cut -d':' -f3 | cut -c 1-1 | xxd  -c 256 -ps | sed "s/..$//")
      hex5=$(/usr/sbin/readlink /sys/class/nvme/nvme1 | sed 's|^.*\(pci.*\)|\1|' | cut -d'/' -f2- | cut -d'/' -f1 | cut -d':' -f3 | cut -c 2-2 | xxd  -c 256 -ps | sed "s/..$//")
      hex6=$(/usr/sbin/readlink /sys/class/nvme/nvme1 | sed 's|^.*\(pci.*\)|\1|' | cut -d'/' -f2- | cut -d'/' -f1 | cut -d':' -f3 | cut -c 4-4 | xxd  -c 256 -ps | sed "s/..$//")
      nvme2hex=$(echo "$hex4$hex5 2e$hex6")
      echo $nvme2hex

      nvme4hex=$(echo "3a$hex4 $hex5/2e $hex6/00" | sed "s/\///g" )
      echo $nvme4hex
  fi

  if [ $(uname -a | grep '4.4.302+' | wc -l) -gt 0 ]; then
    #nvmefile="${libPath}/libsynonvme.so.7.2"
    #if [ $(uname -u | cut -d '_' -f2 | grep 'geminilake\|v1000\|r1000' | wc -l) -gt 0 ]; then
    #  cp -vf ${nvmefile} /etc/libsynonvme.so.1
    #fi
    #if [ $(uname -a | grep '918+\|1019+\|1621xs+' | wc -l) -gt 0 ]; then
      nvmefile="${libPath}/libsynonvme.so.7.2.xxd"
    #fi
  elif [ $(uname -a | grep '4.4.108+' | wc -l) -gt 0 ]; then
    nvmefile="${libPath}/libsynonvme.so.7.1"
  fi  

  if [ $(uname -a | grep '918+' | wc -l) -gt 0 ]; then
    if [ $(echo $nvmepath2 | wc -w) -gt 0 ]; then
        xxd -c 256 ${nvmefile} | sed "s/3a31 332e 3100/$nvme1hex/" | sed "s/3133 2e32/$nvme2hex/" | xxd -c 256 -r > /etc/libsynonvme.so.1
    else
        xxd -c 256 ${nvmefile} | sed "s/3a31 332e 3100/$nvme1hex/" | xxd -c 256 -r > /etc/libsynonvme.so.1
    fi
  elif [ $(uname -a | grep '1019+' | wc -l) -gt 0 ]; then
    xxd ${nvmefile} | sed "s/3134 2e31/$nvme3hex/" | xxd -r > /etc/libsynonvme.so.1
  elif [ $(uname -a | grep '1621xs+' | wc -l) -gt 0 ]; then
    if [ $(echo $nvmepath2 | wc -w) -gt 0 ]; then
        xxd -c 256 ${nvmefile} | sed "s/3031 2e31/$nvme3hex/" | sed "s/3a30 312e 3000/$nvme4hex/" | xxd -c 256 -r > /etc/libsynonvme.so.1
    else
        xxd -c 256 ${nvmefile} | sed "s/3031 2e31/$nvme3hex/" | xxd -c 256 -r > /etc/libsynonvme.so.1
    fi
  else
    rm -f /etc/extensionPorts
    echo "[pci]" >/etc/extensionPorts
    chmod 755 /etc/extensionPorts

    COUNT=1
    NVME_PORTS=$(ls /sys/class/nvme | wc -w)
    for I in $(seq 0 $((${NVME_PORTS} - 1))); do  
      _PATH=$(readlink /sys/class/nvme/nvme${I} | sed 's|^.*\(pci.*\)|\1|' | cut -d'/' -f2- | cut -d'/' -f1) 
      echo "pci${COUNT}=\"${_PATH}\"" >>/etc/extensionPorts ;   COUNT=$((${COUNT} + 1))
    done
    cat /etc/extensionPorts
  fi
}

function modify_synoinfo() {

# add supportnvme="yes" , support_m2_pool="yes" to /etc/synoinfo.conf 2023.02.10
  if [ -f ${tmpRoot}/etc/synoinfo.conf ]; then
    echo 'add supportnvme="yes" to ${tmpRoot}/etc/synoinfo.conf'
    if grep -q 'supportnvme' ${tmpRoot}/etc/synoinfo.conf; then
      sed -i 's#supportnvme=.*#supportnvme="yes"#' ${tmpRoot}/etc/synoinfo.conf
    else
      echo 'supportnvme="yes"' >> ${tmpRoot}/etc/synoinfo.conf
    fi
    cat ${tmpRoot}/etc/synoinfo.conf | grep supportnvme
      
    echo 'add support_m2_pool="yes" to ${tmpRoot}/etc/synoinfo.conf'
    if grep -q 'support_m2_pool' ${tmpRoot}/etc/synoinfo.conf; then
      sed -i 's#support_m2_pool=.*#support_m2_pool="yes"#' ${tmpRoot}/etc/synoinfo.conf
    else
      echo 'support_m2_pool="yes"' >> ${tmpRoot}/etc/synoinfo.conf
    fi
    cat ${tmpRoot}/etc/synoinfo.conf | grep support_m2_pool
  fi

  if [ -f ${tmpRoot}/etc.defaults/synoinfo.conf ]; then
    echo 'add supportnvme="yes" to ${tmpRoot}/etc.defaults/synoinfo.conf'
    if grep -q 'supportnvme' ${tmpRoot}/etc.defaults/synoinfo.conf; then
      sed -i 's#supportnvme=.*#supportnvme="yes"#' ${tmpRoot}/etc.defaults/synoinfo.conf
    else
      echo 'supportnvme="yes"' >> ${tmpRoot}/etc.defaults/synoinfo.conf
    fi
    cat ${tmpRoot}/etc.defaults/synoinfo.conf | grep supportnvme
      
    echo 'add support_m2_pool="yes" to ${tmpRoot}/etc.defaults/synoinfo.conf'
    if grep -q 'support_m2_pool' ${tmpRoot}/etc.defaults/synoinfo.conf; then
      sed -i 's#support_m2_pool=.*#support_m2_pool="yes"#' ${tmpRoot}/etc.defaults/synoinfo.conf
    else
      echo 'support_m2_pool="yes"' >> ${tmpRoot}/etc.defaults/synoinfo.conf
    fi
    cat ${tmpRoot}/etc.defaults/synoinfo.conf | grep support_m2_pool
  fi

}

function run_modules() {
  echo "nvme-cache - modules"
  if [ $dsmMode = "ON" ]; then
      echo "Nothing to install in DSM mode"
  else
      echo "Installing NVMe cache enabler tools readlink"
      cp -vf readlink /usr/sbin/
      cp -vf xxd /usr/sbin/
      chmod 755 /usr/sbin/readlink /usr/sbin/xxd
  fi
  prepare_nvme
}

function run_late() {
  echo "nvme-cache - late"
  echo "Activate NVMe cache"
  if [ $(uname -a | grep '918+\|1019+\|1621xs+' | wc -l) -gt 0 ]; then
    echo "Copy libsynonvme.so.1 file to tmpRoot"
    cp -vf /etc/libsynonvme.so.1 ${tmpRoot}/lib64/
  else
    #if [ $(uname -u | cut -d '_' -f2 | grep 'geminilake\|v1000\|r1000' | wc -l) -gt 0 ]; then
    #  cp -vf /etc/libsynonvme.so.1 ${tmpRoot}/lib64/
    #fi
    cat /etc/extensionPorts
    cp -vf /etc/extensionPorts ${tmpRoot}/etc/
    cp -vf /etc/extensionPorts ${tmpRoot}/etc.defaults/
  fi
  modify_synoinfo
}

if [ $dsmMode = "ON" ]; then
  run_modules
  run_late
else
  if [ "${1}" = "modules" ]; then
    run_modules
  elif [ "${1}" = "late" ]; then
    run_late
  fi
fi

