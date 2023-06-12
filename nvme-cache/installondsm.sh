#!/bin/sh
echo "Installing NVMe cache enabler service"
curl -kL https://github.com/PeterSuh-Q3/tcrp-addons/raw/main/nvme-cache/src/nvme-cache.sh -o /usr/sbin/nvme-cache.sh
chmod 755 /usr/sbin/nvme-cache.sh
cat > /etc/systemd/system/nvme-cache.service <<'EOF'
[Unit]
Description=NVMe cache enabler schedule
[Service]
Type=oneshot
ExecStart=/usr/sbin/nvme-cache.sh
[Install]
WantedBy=multi-user.target
EOF
mkdir -p /etc/systemd/system/multi-user.target.wants
ln -sf /etc/systemd/system/nvme-cache.service /etc/systemd/system/multi-user.target.wants/nvme-cache.service
