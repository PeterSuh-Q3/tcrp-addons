# syno-hdd-db (HDD/SSD/NVMe DB Patch Script)

`syno-hdd-db.sh` is a lightweight, on-device version of the drive-compatibility
database patcher used in this repository. It scans the drives currently
attached to the running DSM system (SATA, SAS, and NVMe) and, for any drive
model that is not already listed in Synology's host compatibility database,
appends a "supported" entry for it to `/etc/disk_db.json` so that DSM stops
reporting the drive as unsupported/incompatible.

## Credit

This script is based on and ported from **[007revad/Synology_HDD_db](https://github.com/007revad/Synology_HDD_db)**.
Core logic — such as detecting installed drives from `/sys/block`, cleaning up
vendor-prefixed or suffixed drive model strings (`fixdrivemodel`), and reading
drive model/firmware information to build compatibility entries — is adapted
directly from that project's `syno_hdd_db.sh`.

All credit for the original design, drive-model quirks handling, and ongoing
research into Synology's disk compatibility database goes to
[@007revad](https://github.com/007revad). Please refer to the upstream
repository for the full-featured, actively maintained version of this tool,
including support for expansion units, M.2 PCIe cards, SAS/SCSI enclosures,
and many additional edge cases that this simplified script does not attempt
to cover.

If you are looking for a general-purpose, standalone HDD/SSD/NVMe database
patcher to run on a normal DSM installation, use the upstream script instead:
https://github.com/007revad/Synology_HDD_db

## What this script does

1. Detects the NAS model from `uname -u` and locates the matching host
   compatibility database file under `/var/lib/disk-compatibility/`
   (`*_host_v7.db`).
2. Iterates over every block device under `/sys/block/*` and classifies it as:
   - `sd*`, `hd*`, `sata*`, `sas*` → SATA/SAS drive
   - `nvme*` → NVMe drive
3. Skips any device that is mounted via USB.
4. Reads the drive model (`/sys/block/<dev>/device/model`) and firmware
   revision:
   - SATA/SAS: via `hdparm -I` (or a fixed value for SAS drives).
   - NVMe: via `/sys/block/<dev>/device/firmware_rev`.
5. Cleans up the raw model string (`fixdrivemodel`) by stripping known vendor
   prefixes (`WDC `, `HGST `, `TOSHIBA `, `Hitachi `, `SAMSUNG `, `FUJISTU `,
   `APPLE HDD `) and known Samsung/Lenovo SSD suffixes (` 00Y...`).
6. If the model is already present in the host `*_host_v7.db` file, it is
   skipped. Otherwise, a new `"support"` compatibility entry is written (or
   merged) into `/etc/disk_db.json` for that model/firmware combination.

## Usage

Run the script as root on a booted DSM/redpill system:

```bash
./syno-hdd-db.sh
```

The resulting `/etc/disk_db.json` can then be reviewed and merged into the
active compatibility database as needed.

## Limitations

This is a minimal, repository-local adaptation intended for use inside the
tinycore-redpill build/boot environment. It does not implement all the
features, drive-model edge cases, or safety checks found in the upstream
[007revad/Synology_HDD_db](https://github.com/007revad/Synology_HDD_db)
project. For production use on a regular DSM installation, prefer the
upstream script.
