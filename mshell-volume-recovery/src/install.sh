#!/bin/sh
# Stage the DSM-side volume recovery helper and its rc.d entrypoint.
set -eu
ROOT=${TMPROOT:-/tmpRoot}
case "${1:-}" in
  late) ;;
  *) exit 0 ;;
esac
[ -d "$ROOT/usr" ] || { echo "mshell-volume-recovery: DSM root missing: $ROOT" >&2; exit 1; }
SRC=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
APP="$ROOT/usr/local/libexec/mshell-volume-recovery"
RCD="$ROOT/usr/local/etc/rc.d"
mkdir -p "$APP" "$RCD"
cp "$SRC/volume-recovery.sh" "$APP/volume-recovery.sh"
chmod 0755 "$APP/volume-recovery.sh"
cat > "$RCD/S99mshell-volume-recovery.sh" <<'HOOK'
#!/bin/sh
APP=/usr/local/libexec/mshell-volume-recovery/volume-recovery.sh
case "${1:-start}" in
  start|"")
    [ -x "$APP" ] || exit 0
    (trap '' HUP; exec "$APP" </dev/null >>/var/log/mshell-volume-recovery.log 2>&1) &
    ;;
  stop) ;;
esac
exit 0
HOOK
chmod 0755 "$RCD/S99mshell-volume-recovery.sh"
echo "mshell-volume-recovery: staged DSM rc.d hook in $ROOT"
