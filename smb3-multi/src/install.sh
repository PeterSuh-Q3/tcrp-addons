#!/usr/bin/env ash

if [ "${1}" = "late" ]; then
  echo "smb3-multi - late"
  echo "Installing smb3 multi channel enabler tools"
  cp -vf smb3-multi.sh /tmpRoot/usr/sbin/smb3-multi.sh
  chmod 755 /tmpRoot/usr/sbin/smb3-multi.sh
  cat > /tmpRoot/usr/lib/systemd/system/smb3-multi.service <<'EOF'
[Unit]
Description=smb3 multi channel enabler schedule
[Service]
Type=oneshot
ExecStart=/usr/sbin/smb3-multi.sh
[Install]
WantedBy=multi-user.target
EOF
  mkdir -p /tmpRoot/usr/lib/systemd/system/multi-user.target.wants
  ln -sf /usr/lib/systemd/system/smb3-multi.service /tmpRoot/usr/lib/systemd/system/multi-user.target.wants/smb3-multi.service
fi
