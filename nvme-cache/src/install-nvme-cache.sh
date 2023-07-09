#!/bin/bash

function active_nvme() {

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
    nvmefile="./libsynonvme.so.7.2"
  elif [ $(uname -a | grep '4.4.108+' | wc -l) -gt 0 ]; then
    nvmefile="./libsynonvme.so.7.1"  
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
      if [ $(echo $nvmepath1 | wc -w) -gt 0 ]; then
          rm -f /etc/extensionPorts
          echo "[pci]" > /etc/extensionPorts
          echo "pci1=\"$nvmepath1\"" >> /etc/extensionPorts
          chmod 755 /etc/extensionPorts

          cat /etc/extensionPorts
      fi

      if [ $(echo $nvmepath2 | wc -w) -gt 0 ]; then
          echo "pci2=\"$nvmepath2\"" >> /etc/extensionPorts

          cat /etc/extensionPorts
      fi
  fi

# add supportnvme="yes" , support_m2_pool="yes" to /etc/synoinfo.conf 2023.02.10
  if [ -f /etc/synoinfo.conf ]; then
    echo 'add supportnvme="yes" to /etc/synoinfo.conf'
    if grep -q 'supportnvme' /etc/synoinfo.conf; then
      sed -i 's#supportnvme=.*#supportnvme="yes"#' /etc/synoinfo.conf
    else
      echo 'supportnvme="yes"' >> /etc/synoinfo.conf
    fi
    cat /etc/synoinfo.conf | grep supportnvme
      
    echo 'add support_m2_pool="yes" to /etc/synoinfo.conf'
    if grep -q 'support_m2_pool' /etc/synoinfo.conf; then
      sed -i 's#support_m2_pool=.*#support_m2_pool="yes"#' /etc/synoinfo.conf
    else
      echo 'support_m2_pool="yes"' >> /etc/synoinfo.conf
    fi
    cat /etc/synoinfo.conf | grep support_m2_pool

# add supportraidgroup="no" , support_syno_hybrid_raid="yes" to /etc/synoinfo.conf for avtive SHR 2023.07.10    
    echo 'add supportraidgroup="no" to /etc/synoinfo.conf'
    if grep -q 'supportraidgroup' /etc/synoinfo.conf; then
      sed -i 's#supportraidgroup=.*#supportraidgroup="no"#' /etc/synoinfo.conf
    else
      echo 'supportraidgroup="no"' >> /etc/synoinfo.conf
    fi
    cat /etc/synoinfo.conf | grep supportraidgroup

    echo 'add support_syno_hybrid_raid="yes" to /etc/synoinfo.conf'
    if grep -q 'support_syno_hybrid_raid' /etc/synoinfo.conf; then
      sed -i 's#support_syno_hybrid_raid=.*#support_syno_hybrid_raid="yes"#' /etc/synoinfo.conf
    else
      echo 'support_syno_hybrid_raid="yes"' >> /etc/synoinfo.conf
    fi
    cat /etc/synoinfo.conf | grep support_syno_hybrid_raid
  fi

}

if [ `mount | grep tmpRoot | wc -l` -gt 0 ] ; then
    HASBOOTED="yes"
    echo "System passed junior"
else
    echo "System is booting"
    HASBOOTED="no"
fi

if [ "$HASBOOTED" = "no" ]; then
  echo "nvme-cache - early"
  echo "Installing NVMe cache enabler tools readlink"

  cp -vf readlink /usr/sbin/
  cp -vf xxd /usr/sbin/
  chmod 755 /usr/sbin/readlink /usr/sbin/xxd

  active_nvme

elif [ "$HASBOOTED" = "yes" ]; then
  echo "nvme-cache - late"
  echo "Installing NVMe cache enabler tools"

  if [ $(uname -a | grep '918+\|1019+\|1621xs+' | wc -l) -gt 0 ]; then
    echo "Copy libsynonvme.so.1 file to tmpRoot"
    cp -vf /etc/libsynonvme.so.1 /tmpRoot/lib64/
  else
    cat /etc/extensionPorts
    cp -vf /etc/extensionPorts /tmpRoot/etc/
    cp -vf /etc/extensionPorts /tmpRoot/etc.defaults/
  fi

  cat /etc/synoinfo.conf | grep -e support_m2_pool -e supportnvme
  cp -vf /etc/synoinfo.conf /tmpRoot/etc/
  cp -vf /etc/synoinfo.conf /tmpRoot/etc.defaults/
fi
