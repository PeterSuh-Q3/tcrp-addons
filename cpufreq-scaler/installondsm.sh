#!/bin/sh

echo "Installing ACPI cpufreq userspace scaler"
cp -vf scaler.sh /usr/sbin/scaler.sh
chmod 755 /usr/sbin/scaler.sh
  cat > /etc/systemd/system/cpufreq-userspace-scaler.service <<'EOF'
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
  mkdir -p /etc/systemd/system/multi-user.target.wants
  ln -sf /etc/systemd/system/cpufreq-userspace-scaler.service /etc/systemd/system/multi-user.target.wants/cpufreq-userspace-scaler.service
