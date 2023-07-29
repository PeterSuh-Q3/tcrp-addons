#!/bin/sh
echo "Installing NVMe cache enabler service"
curl -kL https://github.com/PeterSuh-Q3/tcrp-addons/raw/main/nvme-cache/nvme-service.sh -o /usr/sbin/nvme-service.sh
chmod 755 /usr/sbin/nvme-service.sh
cat > /etc/systemd/system/nvme-cache.service <<'EOF'
[Unit]
Description=NVMe cache enabler schedule
[Service]
Type=oneshot
ExecStart=/usr/sbin/nvme-service.sh
[Install]
WantedBy=multi-user.target
EOF
mkdir -p /etc/systemd/system/multi-user.target.wants
ln -sf /etc/systemd/system/nvme-cache.service /etc/systemd/system/multi-user.target.wants/nvme-cache.service
