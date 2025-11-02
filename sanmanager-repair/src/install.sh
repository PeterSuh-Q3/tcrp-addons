#!/bin/bash

KVER_CLEAN=$(uname -r | sed -n 's/^\([0-9]\+\.[0-9]\+\.[0-9]\+\).*/\1/p')
ZPADKVER=$(printf "%01d%03d%03d\n" $(echo "$KVER_CLEAN" | tr '.' ' '))

if [ "${1}" = "late" ]; then

  if [ "$ZPADKVER" -le 4004059 ]; then
    echo "(Not Supported) nvmevolume-onthefly - ${1}, It does not work on kernel versions 4.4.59 and earlier." 
    exit 0
  fi  

  echo "sanmanager-repair late"
  cp -vf sanrepair.sh /tmpRoot/usr/sbin/sanrepair.sh
  chmod 755 /tmpRoot/usr/sbin/sanrepair.sh
  
  if [ -f /tmpRoot/usr/syno/etc/esynoscheduler/esynoscheduler.db ]; then
    if [ $(/tmpRoot/bin/sqlite3 /tmpRoot/usr/syno/etc/esynoscheduler/esynoscheduler.db "select count(*) as cnt from task a where task_name = 'sanmanager-repair';") -gt "0" ]; then
      echo "A sanmanager-repair task already exists at task_name. skipped!!!"
    else
      echo "insert sanmanager-repair task"
      /tmpRoot/bin/sqlite3 /tmpRoot/usr/syno/etc/esynoscheduler/esynoscheduler.db "INSERT INTO task VALUES('sanmanager-repair', '', 'bootup', '', 1, 0, 0, 0, '', 0, 'while true; do sleep 10; /usr/sbin/sanrepair.sh; [ -d /config/target/loopback ] && break; done', 'script', '{"running":[17917]}', 1706787067, 0, '{}', '{}');"
    fi
  else
    echo "copy sanmanager-repair task db"
    mkdir -p /tmpRoot/usr/syno/etc/esynoscheduler
    cp -f esynoscheduler.db /tmpRoot/usr/syno/etc/esynoscheduler/esynoscheduler.db
  fi

fi
