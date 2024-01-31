#!/bin/bash

if [ "${1}" = "late" ]; then
  echo "Installing daemon for VMM Repair Tool"
  cp -vf vmmrepair.sh /tmpRoot/usr/sbin/vmmrepair.sh
  chmod 755 /tmpRoot/usr/sbin/vmmrepair.sh
  cat > /tmpRoot/etc/systemd/system/vmm-repair.service <<'EOF'
[Unit]
Description=Adds repair VMM
After=multi-user.target
[Service]
User=root
Type=oneshot
RemainAfterExit=true
ExecStart=/usr/sbin/vmmrepair.sh
[Install]
WantedBy=multi-user.target  
EOF
  mkdir -p /tmpRoot/etc/systemd/system/multi-user.target.wants
  ln -sf /etc/systemd/system/vmm-repair.service /tmpRoot/etc/systemd/system/multi-user.target.wants/vmm-repair.service
fi
