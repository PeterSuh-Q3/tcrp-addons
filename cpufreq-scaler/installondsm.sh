#!/bin/sh

#
# Copyright (C) 2023-2026 PeterSuh-Q3
# https://github.com/PeterSuh-Q3
#
# This installer script is licensed under the
# PeterSuh-Q3 Non-Commercial Source-Available License.
#
# The kernel module installed by this script is a separate component
# distributed under its applicable GPL-compatible license.
#
echo "Installing ACPI cpufreq userspace scaler"
cp -vf scaler.sh /usr/sbin/scaler.sh
chmod 755 /usr/sbin/scaler.sh
  cat > /usr/lib/systemd/system/cpufreq-userspace-scaler.service <<'EOF'
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
  mkdir -p /usr/lib/systemd/system/multi-user.target.wants
  ln -sf /usr/lib/systemd/system/cpufreq-userspace-scaler.service /usr/lib/systemd/system/multi-user.target.wants/cpufreq-userspace-scaler.service
