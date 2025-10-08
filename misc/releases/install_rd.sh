#!/bin/sh

ip a
if [ "${1}" = "modules" ]; then
    echo "Starting ttyd, listening on port: 7681"
    tar -zxvf ./lrzsz.tgz -C /usr/sbin
    tar -zxvf ./ttyd.tgz
    ./ttyd login > /dev/null 2>&1 &

elif [ "${1}" = "rcExit" ]; then
  echo "Installing addon misc - ${1}"

  SH_FILE="/usr/syno/share/get_hcl_invalid_disks.sh"
  [ -f "${SH_FILE}" ] && cp -pf "${SH_FILE}" "${SH_FILE}.bak" && printf '#!/bin/sh\nexit 0\n' >"${SH_FILE}"

  mkdir -p /usr/syno/web/webman
  # clear system disk space
  cat >/usr/syno/web/webman/clean_system_disk.cgi <<EOF
#!/bin/sh

echo -ne "Content-type: text/plain; charset=\"UTF-8\"\r\n\r\n"
if [ -b /dev/md0 ]; then
  mkdir -p /mnt/md0
  mount /dev/md0 /mnt/md0/
  rm -rf /mnt/md0/@autoupdate/*
  rm -rf /mnt/md0/upd@te/*
  rm -rf /mnt/md0/.log.junior/*
  umount /mnt/md0/
  rm -rf /mnt/md0/
  echo '{"success": true}'
else
  echo '{"success": false}'
fi
EOF
  chmod +x /usr/syno/web/webman/clean_system_disk.cgi

  # get logs
  cat >/usr/syno/web/webman/get_logs.cgi <<EOF
#!/bin/sh

echo -ne "Content-type: text/plain; charset=\"UTF-8\"\r\n\r\n"
echo "==== proc cmdline ===="
cat /proc/cmdline 
echo "==== SynoBoot log ===="
cat /var/log/linuxrc.syno.log
echo "==== Installerlog ===="
cat /tmp/installer_sh.log
echo "==== Messages log ===="
cat /var/log/messages
EOF
  chmod +x /usr/syno/web/webman/get_logs.cgi

  # recovery.cgi
  cat >/usr/syno/web/webman/recovery.cgi <<EOF
#!/bin/sh

echo -ne "Content-type: text/plain; charset=\"UTF-8\"\r\n\r\n"

echo "Starting ttyd ..."
MSG=""
MSG="\${MSG}MSHELL Recovery Mode\n"
MSG="\${MSG}\n"
MSG="\${MSG}Using terminal commands to modify system configs, execute external binary\n"
MSG="\${MSG}files, add files, or install unauthorized third-party apps may lead to system\n"
MSG="\${MSG}damages or unexpected behavior, or cause data loss. Make sure you are aware of\n"
MSG="\${MSG}the consequences of each command and proceed at your own risk.\n"
MSG="\${MSG}\n"
MSG="\${MSG}Warning: Data should only be stored in shared folders. Data stored elsewhere\n"
MSG="\${MSG}may be deleted when the system is updated/restarted.\n"
MSG="\${MSG}\n"
MSG="\${MSG}To 'Force re-install DSM': please visit http://<ip>:5000/web_install.html\n"
MSG="\${MSG}To 'System partition(/dev/md0) has been mounted to': /tmpRoot\n"
echo -e "\${MSG}" > /etc/motd

/usr/bin/killall ttyd 2>/dev/null || true
./ttyd -W -t titleFixed="MSHELL Recovery" login -f root >/dev/null 2>&1 &

cp -pf /usr/syno/web/web_index.html /usr/syno/web/web_install.html
cp -pf web_index.html /usr/syno/web/web_index.html
mkdir -p /tmpRoot
mount /dev/md0 /tmpRoot
echo "Recovery mode is ready"
EOF
  chmod +x /usr/syno/web/webman/recovery.cgi

  # recovery
  if grep -Eq "recovery" /proc/cmdline 2>/dev/null; then
    /usr/syno/web/webman/recovery.cgi
  fi

#usb nic mac spoofing
    #cmdline=$(cat /proc/cmdline)

    #for i in $(seq 1 8); do
    #    val=$(echo "$cmdline" | grep -o -E "mac${i}=[^ ]+" | cut -d= -f2)
    #    if [ -z "$val" ]; then
    #        break
    #    fi
    #    eval "mac${i}=${val}"
    #done
    
    #ethdevs=$(ls /sys/class/net/ | grep -v lo || true)
    #I=1
    #for eth in $ethdevs; do
    #    curmacmask=$(ip link show $eth | awk '/link\/ether/ {print toupper($2)}')
    #    eval "usrmac=\${mac${I}}"
    #    if [ -n "${usrmac}" ] && [ "${usrmac}" != "null" ]; then
    #        if [ "${curmacmask}" != "${usrmac}" ]; then
    #            echo "Setting MAC Address from ${curmacmask} to ${usrmac} on ${eth}" 
    #            ip link set dev ${eth} address ${usrmac} >/dev/null 2>&1 
    #        else
    #            echo "MAC Address on ${eth} is already set to ${usrmac}, skipping"
    #        fi
    #    fi
    #    I=$((I + 1))
    #    if [ "${eth}" = "eth8" ]; then
    #        break
    #    fi
    #done
    
fi

#echo "Starting dufs ..."
#/usr/bin/killall dufs 2>/dev/null || true
#/usr/sbin/dufs -A -p 7304 / >/dev/null 2>&1 &
