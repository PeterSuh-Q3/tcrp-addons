#!/usr/bin/env ash

MODELS="DS918+ RS1619xs+ DS419+ DS1019+ DS719+ DS1621xs+"
MODEL=$(cat /proc/sys/kernel/syno_hw_version)
tmpRoot="/tmpRoot"

if [ "${1}" = "late" ]; then
  echo "Installing addon nvmecache - ${1}"

  if echo ${MODELS} | grep -q ${MODEL}; then
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
    while read -r N; do
      echo "${num} - ${N}"
      if [ ${num} -eq 1 ]; then
        if [ ${MODEL} = "DS918+" ]; then 
          sed -i "s/0000:00:13.1/${N}/" "${SO_FILE}"
        elif [ ${MODEL} = "RS1619xs+" ]; then
          sed -i "s/0000:00:03.2/${N}/" "${SO_FILE}"
        elif [ ${MODEL} = "DS419+" ]||[ ${MODEL} = "DS1019+" ]; then
          sed -i "s/0000:00:14.1/${N}/" "${SO_FILE}"
        elif [ ${MODEL} = "DS719+" ]||[ ${MODEL} = "DS1621xs+" ]; then
          sed -i "s/0000:00:01.1/${N}/" "${SO_FILE}"
        fi  
      elif [ ${num} -eq 2 ]; then
        if [ ${MODEL} = "DS918+" ]; then 
          sed -i "s/0000:00:13.2/${N}/" "${SO_FILE}"
        elif [ ${MODEL} = "RS1619xs+" ]; then
          sed -i "s/0000:00:03.3/${N}/" "${SO_FILE}"        
        elif [ ${MODEL} = "DS719+" ]||[ ${MODEL} = "DS1621xs+" ]; then
          sed -i "s/0000:00:01.0/${N}/" "${SO_FILE}"        
        fi  
      else
        break
      fi
      num=$((num + 1))
    done < /etc/nvmePorts
  fi
  
fi
