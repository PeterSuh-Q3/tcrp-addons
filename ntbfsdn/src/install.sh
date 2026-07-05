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
# Which box is controller 0 (.1) vs 1 (.2) is decided by MAC address, read from
# user_config.json:
#   { "ntbfsdn": { "mac0": "aa:bb:..", "mac1": "cc:dd:..", "vlan": 100 } }
# If the local MAC matches neither, the addon is a no-op (safe for single node).
#
# Runs in the junior installer runtime (on_patches phase).

[ "${1}" = "patches" ] || exit 0

# Junior installer only - never touch a fully installed DSM (avoids HA side effects)
[ -x /linuxrc.syno ] || exit 0

log(){ echo "ntbfsdn: $*" >&2; }

# --- read config -------------------------------------------------------------
MAC0=""; MAC1=""; VLANID=""
if [ -b /dev/synoboot3 ]; then
  mkdir -p /mnt/tcrp
  mount /dev/synoboot3 /mnt/tcrp 2>/dev/null
  MAC0=$(jq -r -e '.ntbfsdn.mac0' /mnt/tcrp/user_config.json 2>/dev/null)
  MAC1=$(jq -r -e '.ntbfsdn.mac1' /mnt/tcrp/user_config.json 2>/dev/null)
  VLANID=$(jq -r '.ntbfsdn.vlan' /mnt/tcrp/user_config.json 2>/dev/null)
  umount /mnt/tcrp 2>/dev/null
fi
[ "$VLANID" = "null" ] || [ -z "$VLANID" ] && VLANID=100

MAC0=$(echo "$MAC0" | tr 'A-Z' 'a-z')
MAC1=$(echo "$MAC1" | tr 'A-Z' 'a-z')
if [ -z "$MAC0" ] || [ -z "$MAC1" ] || [ "$MAC0" = "null" ] || [ "$MAC1" = "null" ]; then
  log "mac0/mac1 not configured in user_config.json (.ntbfsdn), skipping"
  exit 0
fi

# --- pick primary physical NIC and its MAC -----------------------------------
NIC=""
for d in /sys/class/net/*; do
  n=$(basename "$d")
  [ -e "$d/device" ] || continue   # physical only (skip lo, vlans, dummies)
  NIC="$n"; break
done
[ -z "$NIC" ] && { log "no physical NIC found, skipping"; exit 0; }
LMAC=$(tr 'A-Z' 'a-z' < "/sys/class/net/$NIC/address")

if [ "$LMAC" = "$MAC0" ]; then
  LOC=0; MYIP="169.254.4.1"
elif [ "$LMAC" = "$MAC1" ]; then
  LOC=1; MYIP="169.254.4.2"
else
  log "local MAC $LMAC ($NIC) matches neither mac0 nor mac1, skipping"
  exit 0
fi
log "acting as controller $LOC ($MYIP) via $NIC, ntb_eth0 vlan $VLANID"

# --- 1) fake NTB heartbeat ---------------------------------------------------
# /proc/ntb_heartbeat is created by the synology ntb driver; wait briefly for it.
i=0
while [ ! -e /proc/ntb_heartbeat ] && [ $i -lt 15 ]; do sleep 1; i=$((i+1)); done
if [ -e /proc/ntb_heartbeat ]; then
  if ! mount | grep -q ' /proc/ntb_heartbeat '; then
    echo 1 > /tmp/ntb_hb
    mount -o bind /tmp/ntb_hb /proc/ntb_heartbeat && log "heartbeat forced up"
  fi
else
  log "warning: /proc/ntb_heartbeat absent - heartbeat check may fail"
fi

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
