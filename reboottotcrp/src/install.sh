if [ `mount | grep tmpRoot | wc -l` -gt 0 ] ; then
    HASBOOTED="yes"
    echo "System passed junior"
else
    echo "System is booting"
    HASBOOTED="no"
fi

if [ "$HASBOOTED" = "no" ]; then
  echo "reboottotcrp - early"
elif [ "$HASBOOTED" = "yes" ]; then
  echo "reboottotcrp - late"
  cp -vf tcrp-reboot.sh /tmpRoot/usr/sbin/tcrp-reboot.sh
  chmod 755 /tmpRoot/usr/sbin/tcrp-reboot.sh
  if [ -f /tmpRoot/usr/syno/etc/esynoscheduler/esynoscheduler.db ]; then
    if [ $(/tmpRoot/bin/sqlite3 /tmpRoot/usr/syno/etc/esynoscheduler/esynoscheduler.db "select count(*) as cnt from task a where task_name = 'RebootToTcrp';") -gt "0" ]; then
      echo "A RebootToTcrp task already exists at task_name. skipped!!!"
    else
      echo "insert RebootToTcrp task"
      /tmpRoot/bin/sqlite3 /tmpRoot/usr/syno/etc/esynoscheduler/esynoscheduler.db "INSERT INTO task VALUES('RebootToTcrp', '', '-', '', 0, 0, 0, 0, '', 0, '/usr/sbin/tcrp-reboot.sh', 'script', '{}', '', '', '{}', '{}');"
    fi
  else
    echo "copy RebootToTcrp task db"
    mkdir -p /tmpRoot/usr/syno/etc/esynoscheduler
    cp -f esynoscheduler.db /tmpRoot/usr/syno/etc/esynoscheduler/esynoscheduler.db
  fi
fi
