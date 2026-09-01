#!/usr/bin/env ash

if [ "${1}" = "late" ]; then
  echo "cpufreq-userspace-scaler - late"
  echo "Installing ACPI cpufreq userspace scaler"
  cp -vf scaler.sh /tmpRoot/usr/sbin/scaler.sh
  cp -vf unscaler.sh /tmpRoot/usr/sbin/unscaler.sh
  cp -vf rescaler.sh /tmpRoot/usr/sbin/rescaler.sh
  chmod 755 /tmpRoot/usr/sbin/scaler.sh
  chmod 755 /tmpRoot/usr/sbin/unscaler.sh
  chmod 755 /tmpRoot/usr/sbin/rescaler.sh

  # systemd loads /etc/systemd/system/<unit> in preference to
  # /usr/lib/systemd/system/<unit> of the same name. This addon lived
  # in /etc/systemd/system until 2025-01-12; an old install can still
  # have a leftover copy there that permanently shadows the current
  # /usr/lib/systemd/system unit below (confirmed alongside the same
  # issue in the hdddb addon). Remove it before writing our own copy.
  if [ -f "/tmpRoot/etc/systemd/system/cpufreq-userspace-scaler.service" ]; then
    echo "Removing stale /etc/systemd/system/cpufreq-userspace-scaler.service override from an earlier loader"
    rm -f "/tmpRoot/etc/systemd/system/cpufreq-userspace-scaler.service"
  fi

  cat > /tmpRoot/usr/lib/systemd/system/cpufreq-userspace-scaler.service <<'EOF'
[Unit]
Description=ACPI cpufreq userspace scaler
[Service]
User=root
Restart=on-abnormal
Environment=lowload=150
Environment=midload=250
ExecStart=/usr/sbin/scaler.sh
[Install]
WantedBy=multi-user.target
EOF
  mkdir -p /tmpRoot/usr/lib/systemd/system/multi-user.target.wants
  ln -sf /usr/lib/systemd/system/cpufreq-userspace-scaler.service /tmpRoot/usr/lib/systemd/system/multi-user.target.wants/cpufreq-userspace-scaler.service
#  /tmpRoot/bin/systemctl daemon-reload
#  /tmpRoot/bin/systemctl restart cpufreq-userspace-scaler.service
#  /tmpRoot/bin/systemctl status cpufreq-userspace-scaler.service
fi
