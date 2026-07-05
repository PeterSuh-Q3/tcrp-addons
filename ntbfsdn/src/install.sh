#!/usr/bin/env ash
#
# ntbfsdn - epyc7003ntb (PAS7700 / FS3420) FSDN single-loader install helper.
#
# PAS7700 is a dual-controller (FSDN) Enterprise model. Its DSM installer
# (install.cgi -> scemd) refuses to install unless it can detect a peer
# controller over the NTB link:
#   - /proc/ntb_heartbeat must report "up" (1)
#   - synomulticontroller --is_remote_power_on / --location must succeed
#   - clusterInstall.sh must reach the remote at 169.254.4.{1,2}:5000 over ntb_eth0
#
# On non-Synology hardware there is no NTB PCIe bridge, so none of this comes up.
# This addon lets TWO ordinary boxes (same L2 switch) pose as the two controllers:
#   - fakes /proc/ntb_heartbeat = 1 (bind mount)
#   - builds ntb_eth0 as a VLAN on the primary NIC and assigns 169.254.4.1/.2
#   - wraps synomulticontroller so the peer/location checks pass
# clusterInstall.sh then performs the real coordinated dual-node install over
# regular LAN posing as ntb_eth0.
#
# Junior cannot read user_config.json, so the loader build (functions_t.sh) bakes
# this box's role + NIC MAC into /addons/ntb_eth0.json:
#   { "mac0": "aa:bb:.." , "vlan": 100 }   -> this box is controller 0 (169.254.4.1)
#   { "mac1": "cc:dd:.." , "vlan": 100 }   -> this box is controller 1 (169.254.4.2)
# The recorded MAC selects which physical NIC carries ntb_eth0. If the file is
# absent (non-FSDN build), the addon is a no-op.
#
# Runs in the junior installer runtime (on_patches phase).

[ "${1}" = "patches" ] || exit 0

# Junior installer only - never touch a fully installed DSM (avoids HA side effects)
[ -x /linuxrc.syno ] || exit 0

log(){ echo "ntbfsdn: $*" >&2; }

# --- read baked config -------------------------------------------------------
CFG=/addons/ntb_eth0.json
[ -f "$CFG" ] || { log "no $CFG (non-FSDN build), skipping"; exit 0; }

# MACs may be stored with or without colons (tcrp mac1 has none); normalize.
MAC0=$(jq -r '.mac0 // empty' "$CFG" 2>/dev/null | tr 'A-Z' 'a-z' | tr -d ':')
MAC1=$(jq -r '.mac1 // empty' "$CFG" 2>/dev/null | tr 'A-Z' 'a-z' | tr -d ':')
VLANID=$(jq -r '.vlan // 100' "$CFG" 2>/dev/null)
[ "$VLANID" = "null" ] || [ -z "$VLANID" ] && VLANID=100

if [ -n "$MAC0" ]; then
  LOC=0; MYIP="169.254.4.1"; WANT_MAC="$MAC0"
elif [ -n "$MAC1" ]; then
  LOC=1; MYIP="169.254.4.2"; WANT_MAC="$MAC1"
else
  log "neither mac0 nor mac1 recorded in $CFG, skipping"
  exit 0
fi

# --- pick the physical NIC that carries the recorded MAC ---------------------
NIC=""
for d in /sys/class/net/*; do
  n=$(basename "$d")
  [ -e "$d/device" ] || continue   # physical only (skip lo, vlans, dummies)
  [ "$(tr 'A-Z' 'a-z' < "$d/address" | tr -d ':')" = "$WANT_MAC" ] && { NIC="$n"; break; }
done
[ -z "$NIC" ] && { log "no physical NIC with MAC $WANT_MAC found, skipping"; exit 0; }
log "acting as controller $LOC ($MYIP) via $NIC, ntb_eth0 vlan $VLANID"

# --- 1) fake NTB heartbeat (backgrounded) ------------------------------------
# The synology ntb driver creates /proc/ntb_heartbeat asynchronously, sometimes
# well after this phase runs (observed: present within 15s on one box, much
# later on another). Do NOT block the patches phase waiting for it - that would
# delay boot and can deadlock the very driver load we are waiting on. Instead
# spawn a background watcher that:
#   - waits (up to 5 min) for /proc/ntb_heartbeat to appear, then
#   - keeps it forced to "1" for the install window, re-asserting if the source
#     file in /tmp gets cleaned or the bind mount is lost.
(
  hb_src=/tmp/ntb_hb
  i=0
  while [ ! -e /proc/ntb_heartbeat ] && [ $i -lt 300 ]; do sleep 2; i=$((i+2)); done
  if [ ! -e /proc/ntb_heartbeat ]; then
    log "warning: /proc/ntb_heartbeat never appeared - heartbeat may fail"
    exit 0
  fi
  logged=0
  j=0
  while [ $j -lt 900 ]; do
    if [ ! -e "$hb_src" ] || [ "$(cat /proc/ntb_heartbeat 2>/dev/null)" != "1" ]; then
      echo 1 > "$hb_src"
      umount /proc/ntb_heartbeat 2>/dev/null
      mount -o bind "$hb_src" /proc/ntb_heartbeat
      [ "$logged" = "0" ] && { log "heartbeat forced up"; logged=1; }
    fi
    sleep 5; j=$((j+5))
  done
) &

# --- 2) build ntb_eth0 as a VLAN on the primary NIC --------------------------
modprobe 8021q 2>/dev/null
if ! ip link show ntb_eth0 >/dev/null 2>&1; then
  ip link add link "$NIC" name ntb_eth0 type vlan id "$VLANID" || log "vlan create failed"
fi
ip addr show ntb_eth0 2>/dev/null | grep -q "$MYIP" || ip addr add "$MYIP/24" dev ntb_eth0
ip link set ntb_eth0 up

# --- 3) wrap synomulticontroller so peer/location checks pass ----------------
SMC=/usr/syno/bin/synomulticontroller
REALDIR=/tmp/smc_real
if [ ! -e "$REALDIR/synomulticontroller" ]; then
  mkdir -p "$REALDIR"
  # scemd dispatches on argv[0] basename, so keep the name "synomulticontroller".
  if [ -L "$SMC" ]; then
    ln -sf "$(readlink -f "$SMC")" "$REALDIR/synomulticontroller"
  else
    cp -a "$SMC" "$REALDIR/synomulticontroller"
  fi
fi
cat > /tmp/ntbfsdn_wrap.sh <<WEOF
#!/bin/sh
for a in "\$@"; do
  case "\$a" in
    --is_remote_power_on)  exit 1 ;;   # 1 = remote power on (per clusterInstall.sh)
    --location)            exit $LOC ;; # 0 -> .1, 1 -> .2
    --ntb_heartbeat_check) exit 0 ;;
    --check_chassis_match) exit 0 ;;
  esac
done
exec $REALDIR/synomulticontroller "\$@"
WEOF
chmod +x /tmp/ntbfsdn_wrap.sh
rm -f "$SMC"
cp /tmp/ntbfsdn_wrap.sh "$SMC"
chmod +x "$SMC"
log "synomulticontroller wrapped (location=$LOC)"

log "ready - start DSM install from either node's web UI"
exit 0
