#!/bin/sh
# Stage the DSM-side volume recovery helper and its systemd service.
set -eu
ROOT=${TMPROOT:-/tmpRoot}
case "${1:-}" in
  late) ;;
  *) exit 0 ;;
esac
[ -d "$ROOT/usr" ] || { echo "mshell-volume-recovery: DSM root missing: $ROOT" >&2; exit 1; }
EXTS_ROOT=${MSHELL_EXTS_ROOT:-/exts}
SRC="$EXTS_ROOT/mshell-volume-recovery"
[ -r "$SRC/volume-recovery.sh" ] || {
  echo "mshell-volume-recovery: helper missing: $SRC/volume-recovery.sh" >&2
  exit 1
}
APP="$ROOT/usr/local/libexec/mshell-volume-recovery"
UNIT="$ROOT/usr/lib/systemd/system/mshell-volume-recovery.service"
WANTS="$ROOT/usr/lib/systemd/system/multi-user.target.wants/mshell-volume-recovery.service"

remove_managed_path() {
  path=$1
  if [ -e "$path" ] || [ -L "$path" ]; then
    rm -f "$path"
    echo "mshell-volume-recovery: removed stale startup path $path"
  fi
}

# Remove the old unmanaged startup hook and any older unit/override before
# staging the single systemd-managed boot path.
remove_managed_path "$ROOT/usr/local/etc/rc.d/S99mshell-volume-recovery.sh"
remove_managed_path "$UNIT"
remove_managed_path "$WANTS"
remove_managed_path "$ROOT/etc/systemd/system/mshell-volume-recovery.service"
remove_managed_path "$ROOT/etc/systemd/system/multi-user.target.wants/mshell-volume-recovery.service"

mkdir -p "$APP" "$(dirname "$UNIT")" "$(dirname "$WANTS")"
cp "$SRC/volume-recovery.sh" "$APP/volume-recovery.sh"
chmod 0755 "$APP/volume-recovery.sh"
cat > "$UNIT" <<'UNIT_EOF'
[Unit]
Description=MSHELL addon bounded volume recovery check
After=synoscgi.service nginx.service

[Service]
Type=simple
ExecStart=/bin/sh -c 'exec /usr/local/libexec/mshell-volume-recovery/volume-recovery.sh >>/var/log/mshell-volume-recovery.log 2>&1'
Restart=no
KillMode=control-group
TimeoutStopSec=15

[Install]
WantedBy=multi-user.target
UNIT_EOF
chmod 0644 "$UNIT"
ln -sf /usr/lib/systemd/system/mshell-volume-recovery.service "$WANTS"
echo "mshell-volume-recovery: staged DSM systemd service in $ROOT"
