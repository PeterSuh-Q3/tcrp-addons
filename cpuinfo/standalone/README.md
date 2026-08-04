# cpuinfo — standalone installer

Patches DSM's **Info Center** to show real **CPU temperature**, **fan RPM**,
**GPU model / clock / memory**, and occupied **PCIe slots** — everything the
stock UI hides on unsupported hardware.

This is the standalone counterpart to the
[cpuinfo mshell loader addon](..) — same `cpuinfo.sh`, but installed directly
onto an already-running DSM instead of staged into a loader image at build
time. No loader dependency: works on genuine Synology hardware too.

## 🚀 Install

```bash
curl -sL https://raw.githubusercontent.com/PeterSuh-Q3/tcrp-addons/main/cpuinfo/standalone/install.sh | sudo bash
```

Downloads `cpuinfo.sh` + `mshellscgiproxy`, installs a systemd unit so it
re-applies on every future boot, and applies it immediately — no reboot
needed. Reload Info Center (or hard-refresh the browser tab) afterward.

A second unit (`cpuinfo-gpu.path`) watches for `/dev/nvidia0` and re-applies
once an NVIDIA driver loads later, in case that happens after this script
already ran (harmless no-op on GPU-less or non-NVIDIA hosts).

## How it works

`cpuinfo.sh` does two things:

1. **Patches `admin_center.js`** (with a `.bak` kept alongside it) so DSM's
   Info Center panel *reads* extra fields for CPU temp / fan RPM / GPU info /
   PCIe slots when they're present in the API response — this covers
   DSM ≤ 7.3.
2. **Runs `mshellscgiproxy`**, an intercepting SCGI proxy in front of
   `synoscgi`, and repoints nginx at it. The proxy adds those extra fields to
   the live API response — required for DSM 7.4, which reads GPU info from
   different response fields than the admin_center.js patch alone covers.

## Uninstall

```bash
sudo bash install.sh --uninstall
```

Stops `mshellscgiproxy`, restores `nginx.conf` / `nginx.mustache` from their
`.bak`, removes the systemd units, and deletes the installed files.

## Files

- [install.sh](install.sh) — this installer
- [../src/cpuinfo.sh](../src/cpuinfo.sh) — the actual patch/proxy logic, shared with the loader addon
- [../src/mshellscgiproxy.tgz](../src/mshellscgiproxy.tgz) — prebuilt proxy binary
