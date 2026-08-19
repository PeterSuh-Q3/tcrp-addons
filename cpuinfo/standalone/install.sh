#!/bin/bash
#
# cpuinfo - standalone installer for a running Synology DSM.
#
# Patches DSM's Info Center (admin_center.js) to show real CPU temperature,
# fan RPM, GPU model/clock/memory, and occupied PCIe slots - everything the
# stock UI hides on unsupported hardware. Runs via an intercepting SCGI proxy
# (mshellscgiproxy) that augments DSM API responses; a companion patch also
# covers DSM <= 7.3, which doesn't read the extra fields the proxy injects.
#
# This is the standalone counterpart to the mshell loader addon at
# tcrp-addons/cpuinfo (which stages the same files into a loader image at
# build time via redpill-load's on_os_load hook). Everything this script
# writes goes straight onto the live system instead, and a systemd unit
# keeps it running across reboots without any loader dependency - so it also
# works on genuine Synology hardware, not just mshell-booted boxes.
#
#   sudo bash install.sh                 # after downloading
#   curl -sL <this-url> | sudo bash      # one-liner (prompts read from tty)
#   sudo bash install.sh --uninstall     # revert everything
#
set -u
ask(){ eval "$1=''"; IFS= read -r "$1" </dev/tty 2>/dev/null || true; }

R='\033[0m'; B='\033[1m'; DIM='\033[2m'
RED='\033[1;31m'; GRN='\033[1;32m'; YEL='\033[1;33m'; BLU='\033[1;34m'; WHT='\033[1;37m'
say(){ printf "%b\n" "$*"; }
hr(){  say "${DIM}------------------------------------------------------------${R}"; }
step(){ say "\n${BLU}${B}▶ $*${R}"; }
ok(){   say "  ${GRN}✔${R} $*"; }
warn(){ say "  ${YEL}!${R} $*"; }
err(){  say "  ${RED}x${R} $*"; }
die(){  err "$*"; exit 1; }

REPO_RAW="https://raw.githubusercontent.com/PeterSuh-Q3/tcrp-addons/main/cpuinfo/src"
# $0 is not a usable path when this runs as `curl ... | sudo bash` (the
# README's primary install method) - it's literally the string "bash", since
# there is no real script file. Point every "how to run this again" hint at
# a fresh download instead of `$0`, so the printed command actually works
# regardless of how this copy was invoked.
INSTALL_URL="https://raw.githubusercontent.com/PeterSuh-Q3/tcrp-addons/main/cpuinfo/standalone/install.sh"
INSTALL_HINT="curl -sL ${INSTALL_URL} | sudo bash"
UNINSTALL_HINT="curl -sL ${INSTALL_URL} -o /tmp/cpuinfo-install.sh && sudo bash /tmp/cpuinfo-install.sh --uninstall"
BIN=/usr/sbin/cpuinfo.sh
PROXY=/usr/sbin/mshellscgiproxy
PCI_IDS=/usr/sbin/pci.ids
SVC=/usr/lib/systemd/system/cpuinfo.service
GSVC=/usr/lib/systemd/system/cpuinfo-gpu.service
GPATH=/usr/lib/systemd/system/cpuinfo-gpu.path
WANTS=/usr/lib/systemd/system/multi-user.target.wants

say ""
say "${BLU}${B}  ╔══════════════════════════════════════════════════════════╗${R}"
say "${BLU}${B}  ║   cpuinfo - DSM Info Center CPU/GPU/fan patch (standalone) ║${R}"
say "${BLU}${B}  ╚══════════════════════════════════════════════════════════╝${R}"

# ============================================================ uninstall ==
if [ "${1:-}" = "--uninstall" ] || [ "${1:-}" = "-u" ]; then
  step "Removing cpuinfo"
  if [ "$(id -u 2>/dev/null || echo 1)" != "0" ]; then
    die "Must be run as ${B}root${R}. Try:  ${WHT}${UNINSTALL_HINT}${R}"
  fi
  systemctl disable --now cpuinfo-gpu.path >/dev/null 2>&1
  systemctl stop cpuinfo-gpu.service >/dev/null 2>&1
  systemctl disable --now cpuinfo.service >/dev/null 2>&1
  # cpuinfo.sh's own -s path is the source of truth for undoing the live
  # admin_center.js patch + proxy + nginx repoint - reuse it instead of
  # duplicating that logic here, but only if it's still around to run.
  if [ -x "$BIN" ]; then
    "$BIN" -s
    ok "admin_center.js / nginx / proxy reverted"
  else
    warn "$BIN missing - could not run its restore path; nginx/admin_center.js may be left patched"
    warn "check for *.bak next to /etc/nginx/nginx.conf and /usr/syno/synoman/webman/modules/AdminCenter/admin_center.js"
  fi
  rm -f "$SVC" "$GSVC" "$GPATH" \
        "$WANTS/cpuinfo.service" "$WANTS/cpuinfo-gpu.path" \
        "$BIN" "$PROXY" "$PCI_IDS"
  systemctl daemon-reload >/dev/null 2>&1
  ok "removed"
  exit 0
fi

# ============================================================ 1) ROOT check ==
step "Step 1/5  Privilege check"
if [ "$(id -u 2>/dev/null || echo 1)" != "0" ]; then
  die "Must be run as ${B}root${R}. Try:  ${WHT}${INSTALL_HINT}${R}"
fi
ok "running as root"
command -v systemctl >/dev/null 2>&1 || die "systemd (systemctl) not found - is this DSM 7+?"
command -v curl >/dev/null 2>&1 || die "curl is required but not found."

# ============================================================ 2) fetch ==
step "Step 2/5  Downloading cpuinfo.sh + mshellscgiproxy + pci.ids"
curl -skL "${REPO_RAW}/cpuinfo.sh" -o "$BIN" || die "download failed: cpuinfo.sh"
[ -s "$BIN" ] || die "empty download: cpuinfo.sh"
chmod 755 "$BIN"
ok "cpuinfo.sh -> $BIN"

curl -skL "${REPO_RAW}/mshellscgiproxy.tgz" -o /tmp/mshellscgiproxy.tgz \
  || die "download failed: mshellscgiproxy.tgz"
[ -s /tmp/mshellscgiproxy.tgz ] || die "empty download: mshellscgiproxy.tgz"
tar -zxf /tmp/mshellscgiproxy.tgz -C /usr/sbin || die "extract failed: mshellscgiproxy.tgz"
rm -f /tmp/mshellscgiproxy.tgz
chmod 755 "$PROXY"
ok "mshellscgiproxy -> $PROXY"

# DSM ships pciutils without any pci.ids database, so bare lspci can only
# print "Device <vid>:<did>". This trimmed DB (AMD/ATI, Intel, NVIDIA vendors
# only) lets cpuinfo.sh resolve GPU/PCI names generically via lspci -i.
# Non-fatal: cpuinfo.sh falls back to its small curated table without it.
if curl -skL "${REPO_RAW}/pci.ids.gz" -o /tmp/pci.ids.gz && [ -s /tmp/pci.ids.gz ]; then
  gzip -dc /tmp/pci.ids.gz >"$PCI_IDS" && chmod 644 "$PCI_IDS"
  rm -f /tmp/pci.ids.gz
  ok "pci.ids -> $PCI_IDS"
else
  warn "download failed: pci.ids.gz (non-fatal - GPU/PCI names fall back to the curated table)"
fi

# ============================================ 3) loader version (optional) ==
step "Step 3/5  Loader version (optional)"
# Purely cosmetic: mshellscgiproxy reports this string in Info Center if
# present. Not knowing it does not affect the CPU/GPU/fan patch at all.
if [ -f /usr/mshell/VERSION ]; then
  ok "already set: $(cat /usr/mshell/VERSION 2>/dev/null)"
elif [ -f /addons/VERSION ]; then
  # Present when this happens to run inside a loader build context.
  mkdir -p /usr/mshell
  cp -f /addons/VERSION /usr/mshell/VERSION
  chmod 644 /usr/mshell/VERSION
  ok "seeded from /addons/VERSION: $(cat /usr/mshell/VERSION)"
else
  say "  ${DIM}Not on a loader build - skip, or enter the mshell loader version manually${R}"
  say "  ${DIM}(shown in Info Center only; leave blank to skip).${R}"
  printf "%b" "  ${B}Loader version [blank = skip]: ${R}"
  ask lv
  if [ -n "$lv" ]; then
    mkdir -p /usr/mshell
    printf '%s' "$lv" > /usr/mshell/VERSION
    chmod 644 /usr/mshell/VERSION
    ok "set to '$lv'"
  else
    ok "skipped"
  fi
fi

# ==================================================== 4) systemd units ==
step "Step 4/5  Installing systemd units"
mkdir -p "$(dirname "$SVC")" "$WANTS"

cat > "$SVC" <<UNIT
[Unit]
Description=MSHELL addon cpuinfo daemon
After=synoscgi.service nginx.service

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/bin/bash -c 'sleep 15 && /usr/sbin/cpuinfo.sh > /var/log/cpuinfo_firstboot.log 2>&1'

[Install]
WantedBy=multi-user.target
UNIT
ln -sf "$SVC" "$WANTS/cpuinfo.service"
ok "cpuinfo.service written"

# GPU readiness re-trigger: the NVIDIA proprietary driver (if installed) may
# load after this script already ran once, so a physical/passthrough GPU can
# be missed on the very first pass. Watch /dev/nvidia0 and re-run cpuinfo.sh
# the moment it appears - inert on GPU-less or non-NVIDIA hosts.
cat > "$GSVC" <<UNIT
[Unit]
Description=MSHELL addon cpuinfo GPU refresh (nvidia readiness)

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/sbin/cpuinfo.sh
UNIT

cat > "$GPATH" <<UNIT
[Unit]
Description=MSHELL addon cpuinfo GPU watch (/dev/nvidia0)

[Path]
PathExists=/dev/nvidia0
Unit=cpuinfo-gpu.service

[Install]
WantedBy=multi-user.target
UNIT
ln -sf "$GPATH" "$WANTS/cpuinfo-gpu.path"
ok "cpuinfo-gpu.service + .path written"

systemctl daemon-reload
systemctl enable cpuinfo.service cpuinfo-gpu.path >/dev/null 2>&1
ok "enabled for every future boot"
# `enable` alone only wires the boot-time symlink - a .path unit does not
# actually start *watching* until it (or the boot that WantedBy triggers it
# on) is started. Start it now too, so a GPU driver installed later *in this
# same session* still gets picked up without a reboot (verified: shows
# "active (waiting)" immediately after `systemctl start`, "inactive (dead)"
# with only `enable`). cpuinfo.service itself is intentionally not started
# this way - it's a oneshot we run directly instead, see below.
if systemctl start cpuinfo-gpu.path >/dev/null 2>&1; then
  ok "GPU watch active for the rest of this session too"
else
  warn "could not start cpuinfo-gpu.path now - it will still activate on next boot"
fi

# ==================================================== 5) apply now ==
step "Step 5/5  Applying now"
# The persisted unit sleeps 15s before running - that's there for boot-time
# nginx/synoscgi readiness, not relevant here since DSM is already up. Run
# cpuinfo.sh directly instead of `systemctl start cpuinfo.service`, so this
# applies immediately and its own output/exit code show up right here rather
# than only in the unit's log.
if "$BIN"; then
  ok "patched admin_center.js, started mshellscgiproxy, repointed nginx"
else
  warn "cpuinfo.sh exited non-zero - check: journalctl -u cpuinfo.service (after the next boot) or re-run: sudo $BIN"
fi

hr
say "${GRN}${B}  ✔ SUCCESS${R}  cpuinfo installed and applied."
say "  Reload Info Center (or hard-refresh the browser tab) to see it."
say ""
say "  ${DIM}cpuinfo.service itself shows inactive until the next boot - it ran once${R}"
say "  ${DIM}already, directly, above. That's expected and does not need fixing.${R}"
say "  re-run : ${WHT}sudo $BIN${R}          (re-apply by hand any time)"
say "  logs   : ${WHT}journalctl -u cpuinfo.service${R}  /  ${WHT}cat /var/log/cpuinfo_firstboot.log${R}  (from the next boot on)"
say "  revert : ${WHT}${UNINSTALL_HINT}${R}"
hr
