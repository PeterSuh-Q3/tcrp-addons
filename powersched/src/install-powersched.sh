#!/usr/bin/env ash

if [ "${1}" = "late" ]; then
  echo "Installing powersched tools"
  cp -vf powersched /tmpRoot/usr/sbin/powersched
  chmod 755 /tmpRoot/usr/sbin/powersched

  # systemd loads /etc/systemd/system/<unit> in preference to
  # /usr/lib/systemd/system/<unit> of the same name. This addon lived
  # in /etc/systemd/system until 2025-01-12; an old install can still
  # have a leftover copy there that permanently shadows the current
  # /usr/lib/systemd/system unit below (confirmed alongside the same
  # issue in the hdddb addon). Remove it before writing our own copy.
  if [ -f "/tmpRoot/etc/systemd/system/powersched.timer" ]; then
    echo "Removing stale /etc/systemd/system/powersched.timer override from an earlier loader"
    rm -f "/tmpRoot/etc/systemd/system/powersched.timer"
  fi
  if [ -f "/tmpRoot/etc/systemd/system/powersched.service" ]; then
    echo "Removing stale /etc/systemd/system/powersched.service override from an earlier loader"
    rm -f "/tmpRoot/etc/systemd/system/powersched.service"
  fi

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
