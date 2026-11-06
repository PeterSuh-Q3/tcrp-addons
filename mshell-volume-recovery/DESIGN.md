# Volume recovery retry policy

## Why the permanent marker was removed

The original `reboot-attempted` file blocked every later recovery attempt, even
after a new DSM migration. On the test system it was created at 13:10;
the helper later logged `NOOP: one-shot reboot marker already exists`. This
made a stale record indistinguishable from a reboot loop guard.

## Retry policy

- Ignore the legacy `reboot-attempted` file. Do not require an operator to
  remove it.
- Track attempts in `reboot-retry-state`, scoped to a fingerprint of the DSM
  release/build, DSM model, module type, and registered pool/RAID/volume IDs.
- Permit at most two automatic reboot requests per unresolved failure episode,
  and at most one request during a given kernel boot ID.
- Clear the retry ledger after all registered volumes become mounted and
  writable.
- Start a fresh retry series when the identity fingerprint changes or a new
  `IS_FIRST_LOGIN_AFTER_UPGRADE=1` event is observed in
  `/var/log/synobootup.log`.
- Once two requests have been used for the same unresolved identity, leave the
  system running until it becomes healthy or a new migration/identity event is
  observed. Never perform storage repair or mutate RAID/LVM metadata.

The upgrade event is included because the live test-system `synobootup.log` recorded
`IS_FIRST_LOGIN_AFTER_UPGRADE=1` at 15:38 after its stale 13:10 marker. The
script hashes the full matching log line so a later event can re-arm retries.
This signal and fingerprint behavior still require validation on DSM 7.3 and
on repeated same-model migrations before production-wide deployment. If DSM
does not emit a new event and the identity is unchanged, the retry budget stays
exhausted by design rather than risking an unattended reboot loop.

## Notification

Immediately before requesting a reboot, the helper sends DSM's registered
`StrMgrVolumeOfflineOpPanic` message key to `@administrators`, with the first
failed volume and `볼륨 복구` as substitution values. The message is localized
from DSM's catalog. Notification failure is logged but does not cancel an
otherwise eligible reboot request.
