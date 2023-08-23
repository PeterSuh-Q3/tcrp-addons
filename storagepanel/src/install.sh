#!/usr/bin/env ash

if [ "${1}" = "late" ]; then
  echo "Installing daemon for storagepanel"
  cp -v ./storagepanel.sh /tmpRoot/usr/sbin/storagepanel.sh
  shift
  DEST="/tmpRoot/etc/systemd/system/storagepanel.service"
  echo "[Unit]"                                          >${DEST}
  echo "Description=Modify storage panel"               >>${DEST}
  echo "After=multi-user.target"                        >>${DEST}
  echo                                                  >>${DEST}
  echo "[Service]"                                      >>${DEST}
  echo "Type=oneshot"                                   >>${DEST}
  echo "RemainAfterExit=true"                           >>${DEST}
  echo "ExecStart=/usr/sbin/storagepanel.sh $HDD_Bay $SSD_Bay"   >>${DEST}
  echo                                                  >>${DEST}
  echo "[Install]"                                      >>${DEST}
  echo "WantedBy=multi-user.target"                     >>${DEST}

  mkdir -vp /tmpRoot/lib/systemd/system/multi-user.target.wants
  ln -vsf /etc/systemd/system/storagepanel.service /tmpRoot/lib/systemd/system/multi-user.target.wants/storagepanel.service
fi
