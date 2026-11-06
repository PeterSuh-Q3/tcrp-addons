# MSHELL Volume Recovery

DSM-side, fail-closed bounded-retry reboot helper for persistent data-volume
mount failures on BMI2-absent PML systems. On DSM 7, the addon's `late` event
installs a systemd service after the normal CGI/Nginx services. It runs the
runtime helper from `/usr/local/libexec/mshell-volume-recovery/` without
blocking normal service startup. During staging it removes the old
`/usr/local/etc/rc.d/S99mshell-volume-recovery.sh` hook and stale unit overrides,
logging each removed path so the helper cannot start twice through old and new
mechanisms.

The runtime gate requires:

- `/usr/mshell/MODULE_TYPE` equal to `all-modules (PML)` or
  `custom-modules (PML)`;
- DSM 7.3 or newer, parsed from `/etc.defaults/VERSION` or `/etc/VERSION`;
- BMI2 absent from at least one reported CPU flags line;
- an expected volume registered in `/var/lib/space/space_table`.

It waits up to three minutes for registered volumes to become mounted and
writable. On persistent failure it records diagnostics and proceeds only when
space metadata reports assembly eligible with no missing/faulty/dropped disks,
and the expected md array and VG path exist. It sends the DSM catalog notification
`StrMgrVolumeOfflineOpPanic` to `@administrators`, filling in the first failed
volume and the operation label `볼륨 복구`. Notification failure is logged but
does not cancel the reboot attempt. A persistent retry ledger allows at most two
reboot requests per failure episode and one request per boot ID. It resets
automatically when all volumes become writable, the DSM/model/storage identity
changes, or a new `IS_FIRST_LOGIN_AFTER_UPGRADE=1` event appears in
`/var/log/synobootup.log`. The old `reboot-attempted` marker is ignored. After
the retry budget is exhausted, the helper leaves the host running until one of
those reset conditions occurs. No RAID/LVM repair or metadata mutation is
performed.

The service conversion preserves the existing runtime gates and bounded retry
policy. Runtime validation should still cover DSM 7.3/7.4 volume-writability
command behavior and state-table compatibility before enabling it on
production loader builds.
