#!/usr/bin/env sh

# Install the standalone beep utility and create DSM Scheduler entries for
# boot and shutdown.  pcspeaker.ko and pcspkr.ko are intentionally not copied
# here: they are supplied by all-modules and loaded by etc-modules-load.

if [ "${1}" = "late" ]; then
  echo "Installing addon beep - ${1}"

  mkdir -p /tmpRoot/usr/bin /tmpRoot/usr/lib
  cp -pf ./beep /tmpRoot/usr/bin/beep
  chmod 755 /tmpRoot/usr/bin/beep
  cp -pf ./libubsan.so.1 /tmpRoot/usr/lib/libubsan.so.1

  export LD_LIBRARY_PATH=/tmpRoot/bin:/tmpRoot/lib
  ESYNOSCHEDULER_DB="/tmpRoot/usr/syno/etc/esynoscheduler/esynoscheduler.db"
  if [ ! -f "${ESYNOSCHEDULER_DB}" ] || ! /tmpRoot/bin/sqlite3 "${ESYNOSCHEDULER_DB}" ".tables" | grep -wq "task"; then
    echo "beep: DSM Scheduler database is unavailable; tasks were not registered"
    exit 0
  fi

  BOOT_BEEP="/usr/bin/beep -f 500 -l 500 -d 500 -r 1"
  SHUTDOWN_BEEP="/usr/bin/beep -f 500 -l 500 -d 500 -r 1"
  if [ "${2}" = "-m" ]; then
    BOOT_BEEP="/usr/bin/beep -f 523 -l 100 -n -f 659 -l 100 -n -f 784 -l 250"
    SHUTDOWN_BEEP="/usr/bin/beep -f 784 -l 100 -n -f 659 -l 100 -n -f 523 -l 250"
  fi

  /tmpRoot/bin/sqlite3 "${ESYNOSCHEDULER_DB}" <<EOF
DELETE FROM task WHERE task_name LIKE 'BeepOnBootup';
INSERT INTO task VALUES('BeepOnBootup', '', 'bootup', '', 1, 0, 0, 0, '', 0, '${BOOT_BEEP}', 'script', '{}', '', '', '{}', '{}');
DELETE FROM task WHERE task_name LIKE 'BeepOnShutdown';
INSERT INTO task VALUES('BeepOnShutdown', '', 'shutdown', '', 1, 0, 0, 0, '', 0, '${SHUTDOWN_BEEP}', 'script', '{}', '', '', '{}', '{}');
EOF
  echo "beep: DSM boot and shutdown tasks registered"
fi
