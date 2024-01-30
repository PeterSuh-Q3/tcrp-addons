#!/bin/bash

if [ "${1}" = "late" ]; then
  echo "Installing daemon for SAN MANAGER Repait Tool"
  cp -vf sanrepair.sh /tmpRoot/usr/sbin/sanrepair.sh
  chmod 755 /tmpRoot/usr/sbin/sanrepair.sh
  cat > /tmpRoot/etc/systemd/system/sanrepair.timer <<'EOF'
[Unit]
Description=Configure SAN MANAGER Repair schedule
[Timer]
OnCalendar=*-*-* *:*:00
Persistent=true
[Install]
WantedBy=timers.target
EOF
  mkdir -p /tmpRoot/etc/systemd/system/timers.target.wants
  ln -sf /etc/systemd/system/sanrepair.timer /tmpRoot/etc/systemd/system/timers.target.wants/sanrepair.timer
  cat > /tmpRoot/etc/systemd/system/sanmanager-repair.service <<'EOF'
[Unit]
Description=Configure SAN MANAGER Repair schedule
[Service]
User=root
Type=oneshot
ExecStart=/usr/sbin/sanrepair.sh
[Install]
WantedBy=multi-user.target
EOF
  mkdir -p /tmpRoot/etc/systemd/system/multi-user.target.wants
  ln -sf /etc/systemd/system/sanmanager-repair.service /tmpRoot/etc/systemd/system/multi-user.target.wants/sanmanager-repair.service
fi
