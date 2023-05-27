#!/bin/sh
echo "Manual execution scheduler registration for tcrp-reboot.sh"
curl -kL https://github.com/PeterSuh-Q3/tcrp-addons/raw/main/reboottotcrp/src/tcrp-reboot.sh -o /usr/sbin/tcrp-reboot.sh
chmod 755 /usr/sbin/tcrp-reboot.sh
if [ -f /usr/syno/etc/esynoscheduler/esynoscheduler.db ]; then
    echo "insert RebootToTcrp task"
    /bin/sqlite3 /usr/syno/etc/esynoscheduler/esynoscheduler.db "INSERT INTO task VALUES('RebootToTcrp', '', '-', '', 0, 0, 0, 0, '', 0, '/usr/sbin/tcrp-reboot.sh', 'script', '{}', '', '', '{}', '{}');"
else
    echo "copy RebootToTcrp task db"
    mkdir -p /usr/syno/etc/esynoscheduler
    curl -kL https://github.com/PeterSuh-Q3/tcrp-addons/raw/main/reboottotcrp/src/esynoscheduler.db -o /usr/syno/etc/esynoscheduler/esynoscheduler.db
fi
