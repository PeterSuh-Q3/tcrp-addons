#!/bin/sh
set -eu

REPO_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
SOURCE="${REPO_ROOT}/misc/releases/install-all.sh"
TMP=$(mktemp -d "${TMPDIR:-/tmp}/mshell-ovs-network.XXXXXX")
trap 'rm -rf "$TMP"' EXIT HUP INT TERM

# Extract the exact runtime service body embedded by install-all.sh.
START=$(grep -nF 'cat > "${BIN}" <<' "${SOURCE}" | head -n 1 | cut -d: -f1)
[ -n "${START}" ] || { echo "runtime service heredoc not found" >&2; exit 1; }
END=$(awk -v start="${START}" 'NR > start && $0 == "NEOF" { print NR; exit }' "${SOURCE}")
[ -n "${END}" ] || { echo "runtime service heredoc terminator not found" >&2; exit 1; }
sed -n "$((START + 1)),$((END - 1))p" "${SOURCE}" > "${TMP}/mshell-network.sh"

ROOT="${TMP}/fixture"
mkdir -p "${ROOT}/sys/class/net/eth0" "${ROOT}/sys/class/net/eth1" \
  "${ROOT}/proc" "${ROOT}/etc/sysconfig/network-scripts" "${TMP}/bin"
printf '%s\n' '00:11:32:fa:6c:d3' > "${ROOT}/sys/class/net/eth0/address"
printf '%s\n' '00:11:32:fa:6c:d4' > "${ROOT}/sys/class/net/eth1/address"
printf '%s\n' \
  'DEVICE=eth0' 'BRIDGE=ovs_eth0' > "${ROOT}/etc/sysconfig/network-scripts/ifcfg-eth0"
printf '%s\n' \
  'DEVICE=ovs_eth0' 'BOOTPROTO=dhcp' 'TYPE=OVS' 'PRIMARY=eth0' \
  > "${ROOT}/etc/sysconfig/network-scripts/ifcfg-ovs_eth0"
printf '%s\n' \
  'DEVICE=eth1' 'BRIDGE=ovs_eth1' > "${ROOT}/etc/sysconfig/network-scripts/ifcfg-eth1"
printf '%s\n' \
  'DEVICE=ovs_eth1' 'BOOTPROTO=dhcp' 'TYPE=OVS' 'PRIMARY=eth1' \
  > "${ROOT}/etc/sysconfig/network-scripts/ifcfg-ovs_eth1"

# Point only the extracted copy at disposable fixtures.  All operational
# commands are replaced with stubs; no host networking changes occur.
perl -pi -e "s#\Q/sys/class/net\E#${ROOT}/sys/class/net#g; s#\Q/proc/cmdline\E#${ROOT}/proc/cmdline#g; s#\Q/etc/sysconfig/network-scripts\E#${ROOT}/etc/sysconfig/network-scripts#g; s#\Q/etc/sysconfig/mshell-network-cmdline.txt\E#${ROOT}/etc/sysconfig/mshell-network-cmdline.txt#g; s#\Q/etc/rc.network_routing\E#${TMP}/rc-network-routing#g; s#\Q/etc/rc.network\E#${TMP}/rc-network#g" "${TMP}/mshell-network.sh"

REAL_SED=$(command -v sed)
export REAL_SED
cat > "${TMP}/bin/sed" <<'SED_STUB'
#!/bin/sh
if [ "${1:-}" = "-i" ]; then
  shift
  if [ "$(uname -s)" = Darwin ]; then
    exec "$REAL_SED" -i '' "$@"
  fi
  exec "$REAL_SED" -i "$@"
fi
exec "$REAL_SED" "$@"
SED_STUB
cat > "${TMP}/bin/systemctl" <<'SYSTEMCTL_STUB'
#!/bin/sh
printf '%s\n' "$*" >> "$SYSTEMCTL_LOG"
SYSTEMCTL_STUB
cat > "${TMP}/bin/ip" <<'IP_STUB'
#!/bin/sh
[ "${1:-}" = route ] && [ "${2:-}" = show ] && exit 0
printf '%s\n' "$*" >> "$IP_LOG"
IP_STUB
cat > "${TMP}/bin/route" <<'ROUTE_STUB'
#!/bin/sh
printf '%s\n' "$*" >> "$IP_LOG"
ROUTE_STUB
printf '#!/bin/sh\nexit 0\n' > "${TMP}/rc-network"
printf '#!/bin/sh\nexit 0\n' > "${TMP}/rc-network-routing"
chmod +x "${TMP}/bin/"*
chmod +x "${TMP}/rc-network" "${TMP}/rc-network-routing"
export SYSTEMCTL_LOG="${TMP}/systemctl.log" IP_LOG="${TMP}/ip.log"
PATH="${TMP}/bin:${PATH}"
export PATH

printf '%s\n' \
  'network.001132FA6CD3=192.168.45.11/255.255.255.0/192.168.45.1/210.220.163.82' \
  'network.001132FA6CD4=192.168.45.12/255.255.255.0//' \
  > "${ROOT}/proc/cmdline"
sh "${TMP}/mshell-network.sh"

grep -qx 'BOOTPROTO=static' "${ROOT}/etc/sysconfig/network-scripts/ifcfg-ovs_eth1"
grep -qx 'IPADDR=192.168.45.12' "${ROOT}/etc/sysconfig/network-scripts/ifcfg-ovs_eth1"
grep -qx 'NETMASK=255.255.255.0' "${ROOT}/etc/sysconfig/network-scripts/ifcfg-ovs_eth1"
grep -qx 'BOOTPROTO=static' "${ROOT}/etc/sysconfig/network-scripts/ifcfg-ovs_eth0"
grep -qx 'IPADDR=192.168.45.11' "${ROOT}/etc/sysconfig/network-scripts/ifcfg-ovs_eth0"
grep -q 'mask dhclient@ovs_eth1.service' "${SYSTEMCTL_LOG}"

# Removing a loader static-IP token must also undo the OVS-side configuration.
: > "${ROOT}/proc/cmdline"
sh "${TMP}/mshell-network.sh"
grep -qx 'BOOTPROTO=dhcp' "${ROOT}/etc/sysconfig/network-scripts/ifcfg-ovs_eth1"
! grep -q '^IPADDR=' "${ROOT}/etc/sysconfig/network-scripts/ifcfg-ovs_eth1"
grep -q 'unmask dhclient@ovs_eth1.service' "${SYSTEMCTL_LOG}"

echo "PASS: multi-NIC static addresses apply to OVS bridges and DHCP restoration reverses them"
