# ntbfsdn

Install helper for **epyc7003ntb** (Synology **PAS7700 / FS3420**, DSM 7.4, kernel 5.10.55).

PAS7700 is an FSDN (Failover Storage Dual Node) dual-controller Enterprise
model. Its DSM installer (`install.cgi` → `scemd`) refuses to install unless it
detects a peer controller over the inter-controller **NTB** link:

- `/proc/ntb_heartbeat` must report link up
- `synomulticontroller --is_remote_power_on` / `--location` must succeed
- `clusterInstall.sh` must reach the remote controller at
  `169.254.4.1` / `169.254.4.2` port `5000` over interface `ntb_eth0`

On non-Synology hardware there is no NTB PCIe bridge, so this detection always
fails and the install is blocked.

## What it does

Run on **two ordinary boxes on the same L2 switch**, each booting the
epyc7003ntb loader in junior mode. The addon makes each box pose as one of the
two controllers:

1. **Heartbeat** — bind-mounts `1` over `/proc/ntb_heartbeat`.
2. **ntb_eth0** — creates a VLAN interface (default id `100`) on the primary
   NIC and assigns `169.254.4.1` (controller 0) or `169.254.4.2` (controller 1).
   The two boxes then reach each other over regular LAN posing as `ntb_eth0`.
3. **synomulticontroller wrapper** — forces the peer / location / chassis
   checks to pass.

`clusterInstall.sh` then performs the real coordinated dual-node install between
the two boxes over `ntb_eth0`.

The addon only runs in the junior installer (`/linuxrc.syno` present); it never
touches a fully installed DSM, to avoid interfering with runtime HA logic.

## Configuration

Which box is controller 0 vs 1 is decided by MAC address. Add to
`user_config.json`:

```json
{
  "ntbfsdn": {
    "mac0": "aa:bb:cc:dd:ee:01",
    "mac1": "aa:bb:cc:dd:ee:02",
    "vlan": 100
  }
}
```

- `mac0` — primary NIC MAC of the box that becomes controller 0 (`169.254.4.1`)
- `mac1` — primary NIC MAC of the box that becomes controller 1 (`169.254.4.2`)
- `vlan` — optional VLAN id for `ntb_eth0` (default `100`)

If the local MAC matches neither `mac0` nor `mac1`, the addon is a no-op — safe
to include for single-node epyc7003ntb builds.

## Usage

1. Add `ntbfsdn` to both boxes' loaders and set `mac0`/`mac1` in
   `user_config.json`.
2. Boot both boxes to the DSM installer (junior).
3. Start the DSM install from either box's web UI. The addon has already set up
   the peer link on both sides, so the coordinated install proceeds.

> Reboot resets junior runtime state; the addon re-applies it on each junior
> boot automatically.
