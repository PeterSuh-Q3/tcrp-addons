#!/bin/sh
echo "Installing NVMe cache enabler service"
curl -kL https://github.com/PeterSuh-Q3/tcrp-addons/raw/main/nvme-cache/src/install-nvme-cache.sh -o /usr/sbin/install-nvme-cache.sh
chmod 755 /usr/sbin/install-nvme-cache.sh
curl -kL https://github.com/PeterSuh-Q3/tcrp-addons/raw/main/nvme-cache/releases/readlink -o /usr/sbin/readlink
chmod 755 /usr/sbin/readlink
curl -kL https://github.com/PeterSuh-Q3/tcrp-addons/raw/main/nvme-cache/releases/libsynonvme.so.7.1 -o /lib64/libsynonvme.so.7.1
chmod 755 /lib64/libsynonvme.so.7.1
curl -kL https://github.com/PeterSuh-Q3/tcrp-addons/raw/main/nvme-cache/releases/libsynonvme.so.7.2 -o /lib64/libsynonvme.so.7.2
chmod 755 /lib64/libsynonvme.so.7.2
curl -kL https://github.com/PeterSuh-Q3/tcrp-addons/raw/main/nvme-cache/releases/libsynonvme.so.7.2.xxd -o /lib64/libsynonvme.so.7.2.xxd
chmod 755 /lib64/libsynonvme.so.7.2.xxd
cat > /etc/systemd/system/nvme-cache.service <<'EOF'
[Unit]
Description=NVMe cache enabler schedule
[Service]
Type=oneshot
ExecStart=/usr/sbin/install-nvme-cache.sh
[Install]
WantedBy=multi-user.target
EOF
mkdir -p /etc/systemd/system/multi-user.target.wants
ln -sf /etc/systemd/system/nvme-cache.service /etc/systemd/system/multi-user.target.wants/nvme-cache.service
