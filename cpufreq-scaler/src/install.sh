if [ `mount | grep tmpRoot | wc -l` -gt 0 ] ; then
    HASBOOTED="yes"
    echo "System passed junior"
else
    echo "System is booting"
    HASBOOTED="no"
fi

if [ "$HASBOOTED" = "no" ]; then
  echo "cpufreq-userspace-scaler - early"
elif [ "$HASBOOTED" = "yes" ]; then
  echo "cpufreq-userspace-scaler - late"
  echo "Installing ACPI cpufreq userspace scaler"
  cp -vf scaler.sh /tmpRoot/usr/sbin/scaler.sh
  chmod 755 /tmpRoot/usr/sbin/scaler.sh
  cat > /tmpRoot/etc/systemd/system/cpufreq-userspace-scaler.service <<'EOF'
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
  mkdir -p /tmpRoot/etc/systemd/system/multi-user.target.wants
  ln -sf /etc/systemd/system/cpufreq-userspace-scaler.service /tmpRoot/etc/systemd/system/multi-user.target.wants/cpufreq-userspace-scaler.service
#  /tmpRoot/bin/systemctl daemon-reload
#  /tmpRoot/bin/systemctl restart cpufreq-userspace-scaler.service
#  /tmpRoot/bin/systemctl status cpufreq-userspace-scaler.service
fi
