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
