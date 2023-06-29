#!/bin/bash

function active_nvme() {

  echo "Collecting 1st nvme paths"
  nvmepath1=$(/usr/sbin/readlink /sys/class/nvme/nvme0 | sed 's|^.*\(pci.*\)|\1|' | cut -d'/' -f2- | cut -d'/' -f1)
  echo "Found local 1st nvme with path $nvmepath1"
  if [ $(echo $nvmepath1 | wc -w) -eq 0 ]; then
      echo "Not found local 1st nvme"
      exit 0
  else
      hex1=$(/usr/sbin/readlink /sys/class/nvme/nvme0 | sed 's|^.*\(pci.*\)|\1|' | cut -d'/' -f2- | cut -d'/' -f1 | awk -F ":" '{print $3}' | cut -c 1-1 | xxd  -c 256 -ps | sed "s/..$//")
      hex2=$(/usr/sbin/readlink /sys/class/nvme/nvme0 | sed 's|^.*\(pci.*\)|\1|' | cut -d'/' -f2- | cut -d'/' -f1 | awk -F ":" '{print $3}' | cut -c 2-2 | xxd  -c 256 -ps | sed "s/..$//")
      hex3=$(/usr/sbin/readlink /sys/class/nvme/nvme0 | sed 's|^.*\(pci.*\)|\1|' | cut -d'/' -f2- | cut -d'/' -f1 | awk -F ":" '{print $3}' | cut -c 4-4 | xxd  -c 256 -ps | sed "s/..$//")
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
      hex4=$(/usr/sbin/readlink /sys/class/nvme/nvme1 | sed 's|^.*\(pci.*\)|\1|' | cut -d'/' -f2- | cut -d'/' -f1 | awk -F ":" '{print $3}' | cut -c 1-1 | xxd  -c 256 -ps | sed "s/..$//")
      hex5=$(/usr/sbin/readlink /sys/class/nvme/nvme1 | sed 's|^.*\(pci.*\)|\1|' | cut -d'/' -f2- | cut -d'/' -f1 | awk -F ":" '{print $3}' | cut -c 2-2 | xxd  -c 256 -ps | sed "s/..$//")
      hex6=$(/usr/sbin/readlink /sys/class/nvme/nvme1 | sed 's|^.*\(pci.*\)|\1|' | cut -d'/' -f2- | cut -d'/' -f1 | awk -F ":" '{print $3}' | cut -c 4-4 | xxd  -c 256 -ps | sed "s/..$//")
      nvme2hex=$(echo "$hex4$hex5 2e$hex6")
      echo $nvme2hex

      nvme4hex=$(echo "3a$hex4 $hex5/2e $hex6/00" | sed "s/\///g" )
      echo $nvme4hex
  fi

  if [ $(uname -a | grep '918+\|1019+\|1621xs+' | wc -l) -gt 0 ]; then
      echo "Skip for 918+ 1019+ 1621xs+"
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

# add supportnvme="yes" , support_m2_pool="yes" to /etc.defaults/synoinfo.conf 2023.02.10
  if [ -f /etc/synoinfo.conf ]; then

      echo 'add supportnvme="yes" to /etc/synoinfo.conf'
      /usr/sbin/synosetkeyvalue /etc/synoinfo.conf supportnvme yes
      cat /etc/synoinfo.conf | grep supportnvme
      
      echo 'add support_m2_pool="yes" to /etc/synoinfo.conf'
      /usr/sbin/synosetkeyvalue /etc/synoinfo.conf support_m2_pool yes
      cat /etc/synoinfo.conf | grep support_m2_pool

  fi
  if [ -f /etc.defaults/synoinfo.conf ]; then

      echo 'add supportnvme="yes" to /etc.defaults/synoinfo.conf'
      /usr/sbin/synosetkeyvalue /etc.defaults/synoinfo.conf supportnvme yes
      cat /etc.defaults/synoinfo.conf | grep supportnvme

      echo 'add support_m2_pool="yes" to /etc.defaults/synoinfo.conf'
      /usr/sbin/synosetkeyvalue /etc.defaults/synoinfo.conf support_m2_pool yes
      cat /etc.defaults/synoinfo.conf | grep support_m2_pool

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
#  echo "Installing NVMe cache enabler tools readlink"
  
  #cp -vf libreadline.so.8.0 /lib/
  #cp -vf libsynocore.so.7 /lib/
  #cp -vf libmpfr.so.6.0.1 /lib/
  #cp -vf libsynocredentials.so.7 /lib/
  #chmod 644 /lib/libreadline.so.8.0 /lib/libsynocore.so.7 /lib/libmpfr.so.6.0.1 /lib/libsynocredentials.so.7

  #ln -s /lib/libreadline.so.8.0 /lib/libreadline.so.8
  #ln -s /lib/libreadline.so.8 /lib/libreadline.so
  #ln -s /lib/libsynocore.so.7 /lib/libsynocore.so

  #ln -s /lib/libmpfr.so.6.0.1 /lib/libmpfr.so.6
  #ln -s /lib/libmpfr.so.6.0.1 /lib/libmpfr.so
  #ln -s /lib/libsynocredentials.so.7 /lib/libsynocredentials.so

elif [ "$HASBOOTED" = "yes" ]; then
  echo "nvme-cache - late"
  echo "Installing NVMe cache enabler tools"

  cp -vf readlink /usr/sbin/
  cp -vf xxd /usr/sbin/
  cp -vf gawk /usr/sbin/
  cp -vf synofileutil /usr/sbin/
  chmod 755 /usr/sbin/readlink /usr/sbin/xxd /usr/sbin/gawk /usr/sbin/synofileutil

  ln -s /usr/sbin/gawk /usr/sbin/awk
  ln -s /usr/sbin/synofileutil /usr/sbin/synosetkeyvalue

  active_nvme

  cp -vf /etc/extensionPorts /tmpRoot/etc/extensionPorts
  cp -vf /etc/extensionPorts /tmpRoot/etc.defaults/extensionPorts

  cp -vf /etc/synoinfo.conf /tmpRoot/etc/synoinfo.conf
  cp -vf /etc.defaults/synoinfo.conf /tmpRoot/etc.defaults/synoinfo.conf

  cp -vf nvme-cache.sh /tmpRoot/usr/sbin/nvme-cache.sh
  chmod 755 /tmpRoot/usr/sbin/nvme-cache.sh
  
cat > /tmpRoot/etc/systemd/system/nvme-cache.service <<'EOF'
[Unit]
Description=NVMe cache enabler schedule
[Service]
Type=oneshot
ExecStart=/usr/sbin/nvme-cache.sh
[Install]
WantedBy=multi-user.target
EOF
  mkdir -p /tmpRoot/etc/systemd/system/multi-user.target.wants
  ln -sf /etc/systemd/system/nvme-cache.service /tmpRoot/etc/systemd/system/multi-user.target.wants/nvme-cache.service  
fi
