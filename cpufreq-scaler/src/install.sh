if [ `mount | grep tmpRoot | wc -l` -gt 0 ] ; then
    HASBOOTED="yes"
    echo "System passed junior"
else
    echo "System is booting"
    HASBOOTED="no"
fi

if [ "$HASBOOTED" = "no" ]; then
  echo "smb3-multi - early"
elif [ "$HASBOOTED" = "yes" ]; then
  echo "smb3-multi - late"
  echo "Installing smb3 multi channel enabler tools"
  cp -vf smb3-multi.sh /tmpRoot/usr/sbin/smb3-multi.sh
  chmod 755 /tmpRoot/usr/sbin/smb3-multi.sh
  cat > /tmpRoot/etc/systemd/system/smb3-multi.service <<'EOF'
[Unit]
Description=smb3 multi channel enabler schedule
[Service]
Type=oneshot
ExecStart=/usr/sbin/smb3-multi.sh
[Install]
WantedBy=multi-user.target
EOF
  mkdir -p /tmpRoot/etc/systemd/system/multi-user.target.wants
  ln -sf /etc/systemd/system/smb3-multi.service /tmpRoot/etc/systemd/system/multi-user.target.wants/smb3-multi.service
fi
