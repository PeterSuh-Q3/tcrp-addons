if [ `mount | grep tmpRoot | wc -l` -gt 0 ] ; then
    HASBOOTED="yes"
    echo "System passed junior"
else
    echo "System is booting"
    HASBOOTED="no"
fi

if [ "$HASBOOTED" = "no" ]; then
  echo "nvme-cache - early"
elif [ "$HASBOOTED" = "yes" ]; then
  echo "nvme-cache - late"
  echo "Installing NVMe cache enabler tools"
  cp -vf nvme-cache.sh /tmpRoot/usr/sbin/nvme-cache.sh
  chmod 755 /tmpRoot/usr/sbin/nvme-cache.sh
  cat > /tmpRoot/etc/systemd/system/nvme-cache.service <<'EOF'
[Unit]
Description=NVMe cache enabler schedule
[Service]
Type=oneshot
ExecStart=/usr/sbin/nvme-cache.sh
[Install]
WantedBy=multi-user.target
EOF
  mkdir -p /tmpRoot/etc/systemd/system/multi-user.target.wants
  ln -sf /etc/systemd/system/nvme-cache.service /tmpRoot/etc/systemd/system/multi-user.target.wants/nvme-cache.service
fi
