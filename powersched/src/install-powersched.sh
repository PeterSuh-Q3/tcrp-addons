#!/usr/bin/env ash

if [ "${1}" = "late" ]; then
  echo "Installing powersched tools"
  cp -vf powersched /tmpRoot/usr/sbin/powersched
  chmod 755 /tmpRoot/usr/sbin/powersched
  cat > /tmpRoot/usr/lib/systemd/system/powersched.timer <<'EOF'
[Unit]
Description=Configure RTC to DSM power schedule
[Timer]
OnCalendar=*-*-* *:*:00
Persistent=true
[Install]
WantedBy=timers.target
EOF
  mkdir -p /tmpRoot/usr/lib/systemd/system/timers.target.wants
  ln -sf /usr/lib/systemd/system/powersched.timer /tmpRoot/usr/lib/systemd/system/timers.target.wants/powersched.timer
  cat > /tmpRoot/usr/lib/systemd/system/powersched.service <<'EOF'
[Unit]
Description=Configure RTC to DSM power schedule
[Service]
Type=oneshot
ExecStart=/usr/sbin/powersched
[Install]
WantedBy=multi-user.target
EOF
  mkdir -p /tmpRoot/usr/lib/systemd/system/multi-user.target.wants
  ln -sf /usr/lib/systemd/system/powersched.service /tmpRoot/usr/lib/systemd/system/multi-user.target.wants/powersched.service
fi
