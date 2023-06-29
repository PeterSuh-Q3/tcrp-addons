#!/bin/bash

function active_nvme() {

  echo "Collecting 1st nvme paths"
  nvmepath1=$(readlink /sys/class/nvme/nvme0 | sed 's|^.*\(pci.*\)|\1|' | cut -d'/' -f2- | cut -d'/' -f1)
  echo "Found local 1st nvme with path $nvmepath1"
  if [ $(echo $nvmepath1 | wc -w) -eq 0 ]; then
      echo "Not found local 1st nvme"
      exit 0
  else
      hex1=$(readlink /sys/class/nvme/nvme0 | sed 's|^.*\(pci.*\)|\1|' | cut -d'/' -f2- | cut -d'/' -f1 | awk -F ":" '{print $3}' | cut -c 1-1 | xxd  -c 256 -ps | sed "s/..$//")
      hex2=$(readlink /sys/class/nvme/nvme0 | sed 's|^.*\(pci.*\)|\1|' | cut -d'/' -f2- | cut -d'/' -f1 | awk -F ":" '{print $3}' | cut -c 2-2 | xxd  -c 256 -ps | sed "s/..$//")
      hex3=$(readlink /sys/class/nvme/nvme0 | sed 's|^.*\(pci.*\)|\1|' | cut -d'/' -f2- | cut -d'/' -f1 | awk -F ":" '{print $3}' | cut -c 4-4 | xxd  -c 256 -ps | sed "s/..$//")
      nvme1hex=$(echo "3a$hex1 $hex2/2e $hex3/00" | sed "s/\///g" )
      echo $nvme1hex

      nvme3hex=$(echo "$hex1$hex2 2e$hex3")
      echo $nvme3hex
  fi

  echo ""
  echo "Collecting 2nd nvme paths"
  nvmepath2=$(readlink /sys/class/nvme/nvme1 | sed 's|^.*\(pci.*\)|\1|' | cut -d'/' -f2- | cut -d'/' -f1)
  echo "Found local 2nd nvme with path $nvmepath2"
  if [ $(echo $nvmepath2 | wc -w) -eq 0 ]; then
      echo "Not found local 2nd nvme"
  else
      hex4=$(readlink /sys/class/nvme/nvme1 | sed 's|^.*\(pci.*\)|\1|' | cut -d'/' -f2- | cut -d'/' -f1 | awk -F ":" '{print $3}' | cut -c 1-1 | xxd  -c 256 -ps | sed "s/..$//")
      hex5=$(readlink /sys/class/nvme/nvme1 | sed 's|^.*\(pci.*\)|\1|' | cut -d'/' -f2- | cut -d'/' -f1 | awk -F ":" '{print $3}' | cut -c 2-2 | xxd  -c 256 -ps | sed "s/..$//")
      hex6=$(readlink /sys/class/nvme/nvme1 | sed 's|^.*\(pci.*\)|\1|' | cut -d'/' -f2- | cut -d'/' -f1 | awk -F ":" '{print $3}' | cut -c 4-4 | xxd  -c 256 -ps | sed "s/..$//")
      nvme2hex=$(echo "$hex4$hex5 2e$hex6")
      echo $nvme2hex

      nvme4hex=$(echo "3a$hex4 $hex5/2e $hex6/00" | sed "s/\///g" )
      echo $nvme4hex
  fi

  if [ $(uname -a | grep '918+\|1019+\|1621xs+' | wc -l) -gt 0 ]; then
      echo "Backup & Copy original libsynonvme.so.1 file to root home"
      if [ -f /tmpRoot/lib64/libsynonvme.so.1.bak ]; then
          echo "Found libsynonvme.so.1.bak file"
      else
          cp /tmpRoot/lib64/libsynonvme.so.1 /tmpRoot/lib64/libsynonvme.so.1.bak
      fi    
      cp /tmpRoot/lib64/libsynonvme.so.1.bak /tmpRoot/libsynonvme.so
  fi

  if [ $(uname -a | grep '918+' | wc -l) -gt 0 ]; then
      if [ $(echo $nvmepath2 | wc -w) -gt 0 ]; then
          xxd -c 256 /tmpRoot/libsynonvme.so | sed "s/3a31 332e 3100/$nvme1hex/" | sed "s/3133 2e32/$nvme2hex/" | xxd -c 256 -r > /tmpRoot/lib64/libsynonvme.so.1
      else
          xxd -c 256 /tmpRoot/libsynonvme.so | sed "s/3a31 332e 3100/$nvme1hex/" | xxd -c 256 -r > /tmpRoot/lib64/libsynonvme.so.1
      fi
  elif [ $(uname -a | grep '1019+' | wc -l) -gt 0 ]; then
      xxd /tmpRoot/libsynonvme.so | sed "s/3134 2e31/$nvme3hex/" | xxd -r > /tmpRoot/lib64/libsynonvme.so.1
  elif [ $(uname -a | grep '1621xs+' | wc -l) -gt 0 ]; then
      if [ $(echo $nvmepath2 | wc -w) -gt 0 ]; then
          xxd -c 256 /tmpRoot/libsynonvme.so | sed "s/3031 2e31/$nvme3hex/" | sed "s/3a30 312e 3000/$nvme4hex/" | xxd -c 256 -r > /tmpRoot/lib64/libsynonvme.so.1
      else
          xxd -c 256 /tmpRoot/libsynonvme.so | sed "s/3031 2e31/$nvme3hex/" | xxd -c 256 -r > /tmpRoot/lib64/libsynonvme.so.1
      fi
  else
      if [ $(echo $nvmepath1 | wc -w) -gt 0 ]; then
          rm -f /etc/extensionPorts
          echo "[pci]" > /etc/extensionPorts
          echo "pci1=\"$nvmepath1\"" >> /etc/extensionPorts
          chmod 755 /etc/extensionPorts
          
          cp -vf /etc/extensionPorts /tmpRoot/etc/extensionPorts
          cp -vf /etc/extensionPorts /tmpRoot/etc.defaults/extensionPorts

          cat /etc/extensionPorts
      fi

      if [ $(echo $nvmepath2 | wc -w) -gt 0 ]; then
          echo "pci2=\"$nvmepath2\"" >> /etc/extensionPorts

          cp -vf /etc/extensionPorts /tmpRoot/etc/extensionPorts
          cp -vf /etc/extensionPorts /tmpRoot/etc.defaults/extensionPorts

          cat /etc/extensionPorts
      fi
  fi

  # add supportnvme="yes" , support_m2_pool="yes" to /etc.defaults/synoinfo.conf 2023.02.10
  if [ -f /tmpRoot/etc/synoinfo.conf ]; then

      echo 'add supportnvme="yes" to /tmpRoot/etc/synoinfo.conf'
      /tmpRoot/usr/syno/bin/synosetkeyvalue /tmpRoot/etc/synoinfo.conf supportnvme yes
      cat /tmpRoot/etc/synoinfo.conf | grep supportnvme
      
      echo 'add support_m2_pool="yes" to /tmpRoot/etc/synoinfo.conf'
      /tmpRoot/usr/syno/bin/synosetkeyvalue /tmpRoot/etc/synoinfo.conf support_m2_pool yes
      cat /tmpRoot/etc/synoinfo.conf | grep support_m2_pool

  fi
  if [ -f /tmpRoot/etc.defaults/synoinfo.conf ]; then

      echo 'add supportnvme="yes" to /tmpRoot/etc.defaults/synoinfo.conf'
      /tmpRoot/usr/syno/bin/synosetkeyvalue /tmpRoot/etc.defaults/synoinfo.conf supportnvme yes
      cat /tmpRoot/etc.defaults/synoinfo.conf | grep supportnvme

      echo 'add support_m2_pool="yes" to /tmpRoot/etc.defaults/synoinfo.conf'
      /tmpRoot/usr/syno/bin/synosetkeyvalue /tmpRoot/etc.defaults/synoinfo.conf support_m2_pool yes
      cat /tmpRoot/etc.defaults/synoinfo.conf | grep support_m2_pool

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
elif [ "$HASBOOTED" = "yes" ]; then
  echo "nvme-cache - late"
  echo "Installing NVMe cache enabler tools"
  cp -vf nvme-cache.sh /tmpRoot/usr/sbin/nvme-cache.sh
  cp -vf readlink /tmpRoot/usr/sbin/
  chmod 755 /tmpRoot/usr/sbin/nvme-cache.sh /tmpRoot/usr/sbin/readlink

  active_nvme
fi
