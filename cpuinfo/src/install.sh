#!/usr/bin/env ash

if [ "${1}" = "late" ]; then
  echo "Installing daemon for CPU Info"
  
  cp -vpf cpuinfo.sh /tmpRoot/usr/sbin/cpuinfo.sh
  chmod 755 /tmpRoot/usr/sbin/cpuinfo.sh

  shift
  mkdir -p "/tmpRoot/usr/lib/systemd/system"
  DEST="/tmpRoot/usr/lib/systemd/system/cpuinfo.service"
  {
    echo "[Unit]"
    echo "Description=MSHELL addon cpuinfo daemon"
    echo "After=synoscgi.service nginx.service"
    echo
    echo "[Service]"
    echo "Type=oneshot"
    echo "RemainAfterExit=yes"
    echo "ExecStart=/bin/bash -c 'sleep 15 && /usr/sbin/cpuinfo.sh > /var/log/cpuinfo_firstboot.log 2>&1'"
    echo
    echo "[Install]"
    echo "WantedBy=multi-user.target"
  } >"${DEST}"
  
  mkdir -p /tmpRoot/usr/lib/systemd/system/multi-user.target.wants
  ln -sf /usr/lib/systemd/system/cpuinfo.service /tmpRoot/usr/lib/systemd/system/multi-user.target.wants/cpuinfo.service

  # mshellscgiproxy (built by .github/workflows/build-mshellscgiproxy.yml)
  if [ -f mshellscgiproxy.tgz ]; then
    tar -zxvf mshellscgiproxy.tgz -C /tmpRoot/usr/sbin
    chmod 755 /tmpRoot/usr/sbin/mshellscgiproxy
  else
    echo "WARNING: mshellscgiproxy.tgz not found; run the GitHub Actions workflow to build it."
  fi

  # Seed /usr/mshell/VERSION from the loader's /addons/VERSION (if present)
  # so mshellscgiproxy has a bootloader version to report on first boot.
  if [ -f /addons/VERSION ]; then
    mkdir -p /tmpRoot/usr/mshell
    cp -vpf /addons/VERSION /tmpRoot/usr/mshell/VERSION
    chmod 644 /tmpRoot/usr/mshell/VERSION
  fi

fi
