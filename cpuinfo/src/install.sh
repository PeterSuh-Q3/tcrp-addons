#!/bin/bash
echo "Installing daemon for CPU Info"
  cp -vf cpuinfo.sh /tmpRoot/usr/sbin/cpuinfo.sh
  chmod 755 /tmpRoot/usr/sbin/cpuinfo.sh
  cat > /tmpRoot/etc/systemd/system/cpuinfo.service <<'EOF'
[Unit]
Description=Adds correct CPU Info, from FOXBI
After=multi-user.target
[Service]
Type=oneshot
RemainAfterExit=true
ExecStart=/usr/sbin/cpuinfo.sh
[Install]
WantedBy=multi-user.target  
EOF
  mkdir -p /tmpRoot/etc/systemd/system/multi-user.target.wants
  ln -sf /etc/systemd/system/cpuinfo.service /tmpRoot/etc/systemd/system/multi-user.target.wants/cpuinfo.service
