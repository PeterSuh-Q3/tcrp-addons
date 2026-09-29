#!/usr/bin/env bash
#
# Copyright (C) 2026 PeterSuh-Q3
# https://github.com/PeterSuh-Q3
#
# This standalone installer is licensed under the
# PeterSuh-Q3 Non-Commercial Source-Available License.
# The downloaded RR scripts retain their original 2022 Ing copyright
# and MIT license notices. The RR binary archive retains its upstream terms.
#
# Install RR sensors tools directly on a running DSM system. Fan control is
# opt-in because fan-to-PWM mappings must be verified for each motherboard.
set -euo pipefail

RAW=https://raw.githubusercontent.com/PeterSuh-Q3/tcrp-addons/main
STATE=/usr/local/share/mshell-sensors-standalone
SERVICE=/usr/lib/systemd/system/sensors.service
DB=/usr/syno/etc/esynoscheduler/esynoscheduler.db
FAN_SCRIPT=/usr/bin/rr-sensors.sh
MANIFEST="$STATE/managed.list"
ARCHIVE_SHA=b816f3edb6105fda6815609b8d4d66ad5054e7dcb80829d960ae6219199adff7
SCRIPT_SHA=21e6fb1b9350ae2e5ff3cfd8e871837c847e81386f0d0fc6457c11eb2b6c7002
WORK=

fail() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
note() { printf '%s\n' "$*"; }
cleanup() { [ -z "$WORK" ] || rm -rf -- "$WORK"; }
trap cleanup EXIT

usage() {
  note 'Usage: sudo bash install.sh [--fan-control | --uninstall]'
  note 'Default: install sensors command-line tools only.'
  note '--fan-control: also enable RR automatic fan control after hardware validation.'
}

MODE=tools
case "${1:-}" in
  '') ;;
  --fan-control) MODE=fan ;;
  --uninstall) MODE=uninstall ;;
  --help|-h) usage; exit 0 ;;
  *) usage; exit 2 ;;
esac
[ "$#" -le 1 ] || { usage; exit 2; }
[ "$(id -u)" -eq 0 ] || fail 'Run as root.'
[ -d /usr/syno ] || fail 'This installer requires a running Synology DSM system.'
command -v systemctl >/dev/null || fail 'systemctl is required.'

restore_managed_files() {
  [ -f "$MANIFEST" ] || return 0
  while IFS= read -r dest; do
    [ -n "$dest" ] || continue
    backup="$STATE/original$dest"
    rm -f -- "$dest"
    if [ -e "$backup" ] || [ -L "$backup" ]; then
      mkdir -p "$(dirname "$dest")"
      cp -a -- "$backup" "$dest"
    fi
  done < "$MANIFEST"
}

if [ "$MODE" = uninstall ]; then
  [ -f "$MANIFEST" ] || fail 'No standalone sensors installation was found.'
  if [ -f "$STATE/fan-control.enabled" ]; then
    systemctl disable --now sensors.service >/dev/null 2>&1 || true
    if [ -f "$STATE/fancontrol-task.created" ] && [ -f "$DB" ]; then
      /bin/sqlite3 "$DB" "DELETE FROM task WHERE task_name='Fancontrol';"
    fi
  fi
  restore_managed_files
  systemctl daemon-reload
  note 'Standalone sensors files removed; any pre-existing files were restored.'
  note 'Existing /etc/fancontrol and DSM fan settings were left unchanged for safety.'
  rm -rf -- "$STATE"
  exit 0
fi

command -v curl >/dev/null || fail 'curl is required.'
command -v sha256sum >/dev/null || fail 'sha256sum is required.'
command -v tar >/dev/null || fail 'tar is required.'
[ -e "$SERVICE" ] && [ ! -f "$STATE/fan-control.enabled" ] &&
  fail 'sensors.service already exists outside this standalone installer.'
if [ "$MODE" = fan ]; then
  [ -f "$DB" ] || fail 'DSM Scheduler database not found; refusing to create a replacement.'
  command -v /bin/sqlite3 >/dev/null || fail 'DSM sqlite3 is required.'
  fan_found=0 pwm_found=0
  for file in /sys/class/hwmon/hwmon*/fan*_input; do
    [ -r "$file" ] && fan_found=1
  done
  for file in /sys/class/hwmon/hwmon*/pwm*; do
    [[ ${file##*/} =~ ^pwm[0-9]+$ ]] && [ -w "$file" ] && pwm_found=1
  done
  [ "$fan_found" -eq 1 ] ||
    fail 'No fan RPM input is exposed by the kernel; fan control was not enabled.'
  [ "$pwm_found" -eq 1 ] ||
    fail 'No writable PWM control is exposed by the kernel; fan control was not enabled.'
fi

WORK=$(mktemp -d /tmp/mshell-sensors.XXXXXX)
curl -fLsS --retry 3 "$RAW/sensors/src/sensors-7.1.tgz" -o "$WORK/sensors-7.1.tgz"
curl -fLsS --retry 3 "$RAW/sensors/src/rr-sensors.sh" -o "$WORK/rr-sensors.sh"
printf '%s  %s\n' "$ARCHIVE_SHA" "$WORK/sensors-7.1.tgz" |
  sha256sum -c - >/dev/null || fail 'RR sensors archive checksum mismatch.'
printf '%s  %s\n' "$SCRIPT_SHA" "$WORK/rr-sensors.sh" |
  sha256sum -c - >/dev/null || fail 'RR fan script checksum mismatch.'
tar -xzf "$WORK/sensors-7.1.tgz" -C "$WORK"

mkdir -p "$STATE/original"
touch "$MANIFEST"
install_file() {
  src=$1 dest=$2
  if ! grep -Fxq -- "$dest" "$MANIFEST"; then
    if [ -e "$dest" ] || [ -L "$dest" ]; then
      mkdir -p "$STATE/original$(dirname "$dest")"
      cp -a -- "$dest" "$STATE/original$dest"
    fi
    printf '%s\n' "$dest" >> "$MANIFEST"
  fi
  mkdir -p "$(dirname "$dest")"
  rm -f -- "$dest"
  cp -a -- "$src" "$dest"
}

for path in \
  bin/sensors-conf-convert \
  lib/libsensors.so.5.0.0 lib/libsensors.so.5 lib/libsensors.so \
  sbin/fancontrol sbin/sensors-detect var/sensors3.conf; do
  install_file "$WORK/$path" "/usr/$path"
done
install_file "$WORK/bin/sensors" /usr/bin/rr-sensors-bin
# The RR binary's default config directory is compiled for its original SPK.
# A standalone DSM install uses the extracted config under /usr/var instead.
cat > "$WORK/sensors-wrapper" <<'WRAPPER'
#!/bin/sh
exec /usr/bin/rr-sensors-bin -c /usr/var/sensors3.conf "$@"
WRAPPER
chmod 755 "$WORK/sensors-wrapper"
install_file "$WORK/sensors-wrapper" /usr/bin/sensors
install_file "$WORK/rr-sensors.sh" "$FAN_SCRIPT"
chmod 755 "$FAN_SCRIPT"
note 'Installed RR sensors tools. Run: sensors'

if [ "$MODE" = fan ]; then
  # Preserve any existing task; never reset the user's modes or enabled state.
  if [ "$(/bin/sqlite3 "$DB" "SELECT COUNT(*) FROM task WHERE task_name='Fancontrol';")" = 0 ]; then
    /bin/sqlite3 "$DB" <<'SQL'
INSERT OR IGNORE INTO task VALUES('Fancontrol', '', 'bootup', '', 0, 0, 0, 0, '', 0, '
#            fullfan        coolfan        quietfan
#               |              |              |
FANMODES=("20 40 255 127" "30 60 255 63" "40 80 192 63")
# 1: MINTEMP  2: MAXTEMP  3: MINSTART  4: MINSTOP
', 'script', '{}', '', '', '{}', '{}');
SQL
    touch "$STATE/fancontrol-task.created"
  fi
  cat > "$WORK/sensors.service" <<'UNIT'
[Unit]
Description=RR addon sensors daemon
After=multi-user.target scemd.service

[Service]
Type=forking
ExecStart=/usr/bin/rr-sensors.sh
ExecReload=/usr/bin/pkill -f /usr/bin/rr-sensors.sh
Restart=always
StartLimitBurst=5
StartLimitInterval=10

[Install]
WantedBy=multi-user.target
UNIT
  install_file "$WORK/sensors.service" "$SERVICE"
  systemctl daemon-reload
  touch "$STATE/fan-control.enabled"
  systemctl enable --now sensors.service
  note 'Fan control enabled. Verify fan RPM and temperatures immediately.'
fi

note 'Uninstall: download this script and run it with --uninstall.'
