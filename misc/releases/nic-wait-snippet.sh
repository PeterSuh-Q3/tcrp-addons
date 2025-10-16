mknod -m 0666 /dev/console c 1 3
echo "[INIT] Waiting up to 190 seconds for NICs (addr_assign_type=0)..."
MAX_WAIT=190
while [ $MAX_WAIT -gt 0 ]; do
  ALL_READY=true
  for dev in $(ls /sys/class/net | grep -v "^lo$"); do
    [ -e "/sys/class/net/$dev/device" ] || continue
    if [ -e "/sys/class/net/$dev/addr_assign_type" ]; then
      TYPE=$(cat "/sys/class/net/$dev/addr_assign_type")
      if [ "$TYPE" != "0" ]; then
        ALL_READY=false
        break
      fi
    else
      MAC=$(cat "/sys/class/net/$dev/address" 2>/dev/null)
      echo "$MAC" | grep -qiE "^[0-9a-f]{2}(:[0-9a-f]{2}){5}$" && \
      [ "$MAC" != "00:00:00:00:00:00" ] || { ALL_READY=false; break; }
    fi
  done
  if [ "$ALL_READY" = true ]; then
    echo "[INIT] All NICs ready. Continuing boot..."
    break
  fi
  echo "[INIT] Waiting... $MAX_WAIT sec left"
  sleep 1
  MAX_WAIT=$((MAX_WAIT - 1))
done
