#!/usr/bin/env ash

if [ "${1}" = "late" ]; then
  echo "patch synology drive database"

  cp -v  ./drivedatabase.sh /tmpRoot/usr/sbin/drivedatabase.sh
  chmod +x /tmpRoot/usr/sbin/drivedatabase.sh

  DEST="/tmpRoot/etc/systemd/system/drivedatabase.service"
  echo "[Unit]"                                    >${DEST}
  echo "Description=Enable M2 volume"             >>${DEST}
  echo "After=multi-user.target"                  >>${DEST}
  echo                                            >>${DEST}
  echo "[Service]"                                >>${DEST}
  echo "Type=oneshot"                             >>${DEST}
  echo "RemainAfterExit=true"                     >>${DEST}
  echo "ExecStart=/usr/sbin/drivedatabase.sh"     >>${DEST}
  echo                                            >>${DEST}
  echo "[Install]"                                >>${DEST}
  echo "WantedBy=multi-user.target"               >>${DEST}

  mkdir -vp /tmpRoot/lib/systemd/system/multi-user.target.wants
  ln -vsf /etc/systemd/system/drivedatabase.service /tmpRoot/lib/systemd/system/multi-user.target.wants/drivedatabase.service

fi
