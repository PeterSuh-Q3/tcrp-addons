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
    echo "beep: installing bundled DSM Scheduler database"
    mkdir -p "$(dirname "${ESYNOSCHEDULER_DB}")"
    cp -pf ./esynoscheduler.db "${ESYNOSCHEDULER_DB}"
  fi

  # TCRP addons do not receive RR-style positional parameters.  Keep the
  # RR -m behaviour as the fixed default: Mario on boot, Axel F on shutdown.
  BOOT_BEEP="/usr/bin/beep -f 130 -l 100 -n -f 262 -l 100 -n -f 330 -l 100 -n -f 392 -l 100 -n -f 523 -l 100 -n -f 660 -l 100 -n -f 784 -l 300 -n -f 660 -l 300 -n -f 146 -l 100 -n -f 262 -l 100 -n -f 311 -l 100 -n -f 415 -l 100 -n -f 523 -l 100 -n -f 622 -l 100 -n -f 831 -l 300 -n -f 622 -l 300 -n -f 155 -l 100 -n -f 294 -l 100 -n -f 349 -l 100 -n -f 466 -l 100 -n -f 588 -l 100 -n -f 699 -l 100 -n -f 933 -l 300 -n -f 933 -l 100 -n -f 933 -l 100 -n -f 933 -l 100 -n -f 1047 -l 400"
  SHUTDOWN_BEEP="/usr/bin/beep -f 659 -l 460 -n -f 784 -l 340 -n -f 659 -l 230 -n -f 659 -l 110 -n -f 880 -l 230 -n -f 659 -l 230 -n -f 587 -l 230 -n -f 659 -l 460 -n -f 988 -l 340 -n -f 659 -l 230 -n -f 659 -l 110 -n -f 1047 -l 230 -n -f 988 -l 230 -n -f 784 -l 230 -n -f 659 -l 230 -n -f 988 -l 230 -n -f 1318 -l 230 -n -f 659 -l 110 -n -f 587 -l 230 -n -f 587 -l 110 -n -f 494 -l 230 -n -f 740 -l 230 -n -f 659 -l 460"

  /tmpRoot/bin/sqlite3 "${ESYNOSCHEDULER_DB}" <<EOF
DELETE FROM task WHERE task_name LIKE 'BeepOnBootup';
INSERT INTO task VALUES('BeepOnBootup', '', 'bootup', '', 1, 0, 0, 0, '', 0, '${BOOT_BEEP}', 'script', '{}', '', '', '{}', '{}');
DELETE FROM task WHERE task_name LIKE 'BeepOnShutdown';
INSERT INTO task VALUES('BeepOnShutdown', '', 'shutdown', '', 1, 0, 0, 0, '', 0, '${SHUTDOWN_BEEP}', 'script', '{}', '', '', '{}', '{}');
EOF
  echo "beep: DSM boot and shutdown tasks registered"
fi
