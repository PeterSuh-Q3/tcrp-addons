#!/usr/bin/env ash

if [ "${1}" = "late" ]; then
  echo "Installing daemon for storagepanel"
  cp -v ./runonce.sh /tmpRoot/usr/sbin/runonce.sh
  chmod +x /tmpRoot/usr/sbin/runonce.sh
  shift
  DEST="/tmpRoot/etc/systemd/system/storagepanel.service"
  echo "[Unit]"                                          >${DEST}
  echo "Description=Modify storage panel"               >>${DEST}
  echo "After=multi-user.target"                        >>${DEST}
  echo                                                  >>${DEST}
  echo "[Service]"                                      >>${DEST}
  echo "Type=oneshot"                                   >>${DEST}
  echo "RemainAfterExit=true"                           >>${DEST}
  echo "ExecStart=/usr/sbin/runonce.sh"                 >>${DEST}
  echo                                                  >>${DEST}
  echo "[Install]"                                      >>${DEST}
  echo "WantedBy=multi-user.target"                     >>${DEST}
  mkdir -vp /tmpRoot/lib/systemd/system/multi-user.target.wants
  ln -vsf /etc/systemd/system/storagepanel.service /tmpRoot/lib/systemd/system/multi-user.target.wants/storagepanel.service

  echo "Installing manual schedule for storagepanel"
  cp -v ./storagepanel.sh /tmpRoot/usr/sbin/storagepanel.sh
  chmod +x /tmpRoot/usr/sbin/storagepanel.sh
  if [ -f /tmpRoot/usr/syno/etc/esynoscheduler/esynoscheduler.db ]; then
    if [ $(/tmpRoot/bin/sqlite3 /tmpRoot/usr/syno/etc/esynoscheduler/esynoscheduler.db "select count(*) as cnt from task a where task_name = 'Change Storage Panel';") -gt "0" ]; then
      echo "A Change Storage Panel task already exists at task_name. skipped!!!"
    else
      echo "insert Change Storage Panel task"
      /tmpRoot/bin/sqlite3 /tmpRoot/usr/syno/etc/esynoscheduler/esynoscheduler.db "INSERT INTO task VALUES('Change Storage Panel', '', '-', '', 0, 0, 0, 0, '', 0, '/usr/sbin/storagepanel.sh TOWER_12_Bay 1X2 # RACK_0_Bay RACK_2_Bay RACK_4_Bay RACK_8_Bay RACK_10_Bay RACK_12_Bay RACK_12_Bay_2 RACK_16_Bay RACK_20_Bay RACK_24_Bay RACK_60_Bay TOWER_1_Bay TOWER_2_Bay TOWER_4_Bay TOWER_4_Bay_J TOWER_4_Bay_S TOWER_5_Bay TOWER_6_Bay TOWER_8_Bay TOWER_12_Bay', 'script', '{}', '', '', '{}', '{}');"
    fi
  fi
fi
