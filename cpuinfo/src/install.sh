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

  # GPU readiness re-trigger: the NVIDIA proprietary driver is loaded late (by
  # its DSM package), well after cpuinfo.service's fixed boot delay, so the
  # first run misses the nvidia GPU. Watch /dev/nvidia0 and re-run cpuinfo.sh
  # once it appears. Intel/AMD are loaded early and already covered by the boot
  # run; on GPU-less or non-nvidia hosts this path simply never fires (inert).
  #
  # The path triggers a SEPARATE oneshot (not cpuinfo.service, which is already
  # active from boot). RemainAfterExit=yes keeps it active after running so the
  # PathExists condition does not retrigger it in a loop.
  GDEST="/tmpRoot/usr/lib/systemd/system/cpuinfo-gpu.service"
  {
    echo "[Unit]"
    echo "Description=MSHELL addon cpuinfo GPU refresh (nvidia readiness)"
    echo
    echo "[Service]"
    echo "Type=oneshot"
    echo "RemainAfterExit=yes"
    echo "ExecStart=/usr/sbin/cpuinfo.sh"
  } >"${GDEST}"

  PDEST="/tmpRoot/usr/lib/systemd/system/cpuinfo-gpu.path"
  {
    echo "[Unit]"
    echo "Description=MSHELL addon cpuinfo GPU watch (/dev/nvidia0)"
    echo
    echo "[Path]"
    echo "PathExists=/dev/nvidia0"
    echo "Unit=cpuinfo-gpu.service"
    echo
    echo "[Install]"
    echo "WantedBy=multi-user.target"
  } >"${PDEST}"

  ln -sf /usr/lib/systemd/system/cpuinfo-gpu.path /tmpRoot/usr/lib/systemd/system/multi-user.target.wants/cpuinfo-gpu.path

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
