#!/usr/bin/env ash

MODELS="DS918+ RS1619xs+ DS419+ DS1019+ DS719+ DS1621xs+"
MODEL=$(cat /proc/sys/kernel/syno_hw_version)

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


if [ "${1}" = "patches" ]; then
  echo "Installing addon nvmecache - ${1}"

  BOOTDISK=""
  devtype="$(blkid | grep "6234-C863" | cut -c 6-7 )"
  if [ "${devtype}" = "sd" ]; then
    BOOTDISK="$(blkid | grep "6234-C863" | cut -c 6-8 )"
  elif [ "${devtype}" = "sa" ]; then
    BOOTDISK="$(blkid | grep "6234-C863" | cut -c 6-10 )"
  elif [ "${devtype}" = "nv" ]; then
    BOOTDISK="$(blkid | grep "6234-C863" | cut -c 6-10 )"
  else
    BOOTDISK="synoboot"
  fi
  [ -n "${BOOTDISK}" ] && BOOTDISK_PHYSDEVPATH="$(cat /sys/block/${BOOTDISK}/uevent | grep 'PHYSDEVPATH' | cut -d'=' -f2)" || BOOTDISK_PHYSDEVPATH=""
  echo "BOOTDISK=${BOOTDISK}"
  echo "BOOTDISK_PHYSDEVPATH=${BOOTDISK_PHYSDEVPATH}"
  rm -f /etc/nvmePorts
  for P in $(ls -d /sys/block/nvme* 2>/dev/null); do
    if [ -n "${BOOTDISK_PHYSDEVPATH}" -a "${BOOTDISK_PHYSDEVPATH}" = "$(cat ${P}/uevent | grep 'PHYSDEVPATH' | cut -d'=' -f2)" ]; then
      echo "bootloader: ${P}"
      continue
    fi
    PCIEPATH=$(cat ${P}/uevent 2>/dev/null | grep 'PHYSDEVPATH' | cut -d'/' -f4)
    if [ -n "${PCIEPATH}" ]; then
      # TODO: Need check?
      MULTIPATH=$(cat ${P}/uevent 2>/dev/null | grep 'PHYSDEVPATH' | cut -d'/' -f5)
      if [ -z "${MULTIPATH}" ]; then
        echo "${PCIEPATH} does not support!"
        continue
      fi
      echo "${PCIEPATH}" >>/etc/nvmePorts
    fi
  done
  [ -f /etc/nvmePorts ] && cat /etc/nvmePorts
  
  if ! echo ${MODELS} | grep -q ${MODEL}; then
    echo "${MODEL} use extensionPorts"
    rm -f /etc/extensionPorts
    echo "[pci]" >/etc/extensionPorts
    chmod 755 /etc/extensionPorts
    
    num=1
    for N in $(cat /etc/nvmePorts 2>/dev/null); do
      echo "${num} - ${N}"
      echo "pci${num}=\"${N}\"" >>/etc/extensionPorts
      num=$((num + 1))
    done
    cat /etc/extensionPorts
  fi

elif [ "${1}" = "late" ]; then
  echo "Installing addon nvmecache - ${1}"

  if ! echo ${MODELS} | grep -q ${MODEL}; then
    echo "${MODEL} use extensionPorts"
    cat /etc/extensionPorts
    cp -vf /etc/extensionPorts ${tmpRoot}/etc/
    cp -vf /etc/extensionPorts ${tmpRoot}/etc.defaults/
  else
  #
  # |       models      |     1st      |     2nd      |
  # | DS918+            | 0000:00:13.1 | 0000:00:13.2 |
  # | RS1619xs+         | 0000:00:03.2 | 0000:00:03.3 |
  # | DS419+, DS1019+   | 0000:00:14.1 |              |
  # | DS719+, DS1621xs+ | 0000:00:01.1 | 0000:00:01.0 |
  #
  # In the late stage, the /sys/ directory does not exist, and the device path cannot be obtained.
  # (/dev/ does exist, but there is no useful information.)
  # (The information obtained by lspci is incomplete and an error will be reported.)
  # Therefore, the device path is obtained in the early stage and stored in /etc/nvmePorts.

    SO_FILE="/tmpRoot/usr/lib/libsynonvme.so.1"
    [ ! -f "${SO_FILE}.bak" ] && cp -vf "${SO_FILE}" "${SO_FILE}.bak"

    cp -vf "${SO_FILE}.bak" "${SO_FILE}"

    num=1
    for N in $(cat /etc/nvmePorts 2>/dev/null); do
      echo "${num} - ${N}"
      if [ ${num} -eq 1 ]; then
        sed -i "s/0000:00:13.1/${N}/; s/0000:00:03.2/${N}/; s/0000:00:14.1/${N}/; s/0000:00:01.1/${N}/" "${SO_FILE}"
      elif [ ${num} -eq 2 ]; then
        sed -i "s/0000:00:13.2/${N}/; s/0000:00:03.3/${N}/; s/0000:00:99.9/${N}/; s/0000:00:01.0/${N}/" "${SO_FILE}"
      else
        break
      fi
      num=$((num + 1))
    done
  fi
  modify_synoinfo
fi
