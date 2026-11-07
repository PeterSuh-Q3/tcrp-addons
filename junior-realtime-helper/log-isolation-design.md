# Junior Realtime Helper log isolation design

**Status:** implemented and pushed; DSM pilot started on 2026-11-07  
**Incident:** DSM 7.4.1 / Docker Joplin, 2026-11-06

## 1. Goal

Prevent the Junior Realtime Helper from producing high-rate output in DSM's
system log directory. Preserve the live status display, including the current
ping response time and two-second refresh, while keeping diagnostic logs small
and useful. This should prevent the helper log from repeatedly entering DSM's
emergency rotation path, whose broad `pkill -SIGHUP -x sh` can affect unrelated
shell processes such as Joplin's command wrapper.

Both this design record and its eventual implementation belong in
`tcrp-addons/junior-realtime-helper`. The loader repository retains only a
short evidence handoff for work that spans the loader and addon.

## 2. Evidence and limits

The attached evidence bundle's internal SHA-256 list was verified. The
installed `selftest.sh` hash exactly matches the file in tcrp-addons commit
`5bf5a1a` (2026-10-27). That code compares and prints a status string which
includes the full ping result, including variable RTT, and redirects helper
stdout/stderr to `/var/log/junior-realtime-helper.log`.

Other high-rate sources are possible in the same version:

- A failed `render_status` writes a diagnostic to stderr every two-second
  loop.
- `kms-display.c` logs a KMS setup failure on each retry; the setup loop retries
  once per second when setup fails.
- Ping RTT changes can make the shell print its status snapshot on successive
  probes even if connectivity remains healthy.

The original 102 MB file and installed helper payload were deleted before the
bundle was made. Its contents and per-source contribution are unavailable.
Consequently, the design removes or rate-limits all persistent high-rate
output instead of attributing the full file size to only one message.

The evidence shows hourly emergency-rotation records and a same-second HUP
trace to the Joplin child shell, followed by Joplin's SIGHUP error (preserved
as an investigation transcript) and Docker `die`/`start` events. The HUP trace
also shows the helper shell's signal ignored. `synologrotated` contains the
matching pkill command string, but its child PPID/argv was not captured, so the
exact caller-to-pkill parent link remains a strong inference. This change
addresses the helper as the log-growth trigger; it does not modify or repair
DSM's global emergency-rotation behavior.

## 3. Behavioral requirements

1. Keep the displayed panel content, two-second probe cadence, QR placement,
   KMS rendering, live RTT value, and `DISPLAY REFRESH` timestamp unchanged.
2. Never write a full status snapshot or an RTT-only change to the persistent
   diagnostic log.
3. Log meaningful state transitions and actionable failures, with timestamps.
4. Bound persistent helper diagnostics and avoid keeping an append file
   descriptor open across log renames.
5. Rate-limit repeated console and KMS failures while preserving retries needed
   for late DRM device availability.
6. Apply the same logging policy to Junior `jrExit` and DSM 7 `late` startup.
7. Do not signal, restart, reconfigure, or otherwise change Joplin, Docker, or
   DSM logging services.

## 4. Proposed logging architecture

### 4.1 Separate status data from diagnostic events

The existing `/tmp/junior-realtime-helper.status` remains the display data
channel and continues to be atomically replaced. It retains all current values,
including RTT and refresh time. `kms-display` continues polling that file and
redrawing its live fields.

The status probe must not print its full snapshot to stdout. Its comparison key
for diagnostics is a normalized state signature containing:

- mode, selected interface, IPv4 address, gateway and link state;
- ping reachability (`REPLY` / `NO_REPLY`), excluding RTT;
- DSM TCP/5000 readiness;
- recognized disk count and disk identities/list.

The helper emits one initial state record and one record when this signature
changes. RTT-only changes and `DISPLAY REFRESH` changes remain visible on screen
but do not produce log records.

### 4.2 Central, bounded diagnostic writer

All persistent helper and KMS messages go through one logger worker owned by
the monitor. The monitor creates a mode-0600 FIFO under `/tmp`, starts the
worker before the KMS renderer, and sends one-line events through that FIFO.
The KMS renderer's stderr is connected to the same event channel. The worker
opens the persistent log by path for each received record, appends it, and
closes it immediately. No long-lived process keeps the persistent log open
across DSM renames. The worker ignores HUP, as does the monitor.

The logger channel is not a fallback for arbitrary shell output: probe
snapshots are removed from stdout, and service wrappers must not redirect the
monitor's complete stdout/stderr stream to the persistent log. If the worker is
unavailable, diagnostic records are dropped without stopping the probe or
blocking screen updates. The implementation must ensure FIFO writes cannot
block indefinitely when the reader has exited.

Initial proposed retention limits:

- active log: at most 256 KiB;
- two compressed or plain rotated records: at most 256 KiB each;
- total helper-owned diagnostic data: at most 768 KiB, excluding filesystem
  metadata.

Rotation is performed only by the single logger owner, before appending a new
record. It must handle a missing file and an external DSM rename without
failing the status monitor. The display/status path continues independently.

The existing `/var/log/junior-realtime-helper.log` path is retained initially
for compatibility with current troubleshooting habits. The cap is deliberately
far below the observed ~100 MiB incident file. The exact DSM fallback threshold
is not assumed; the pilot must verify that the bounded log does not trigger
emergency rotation. If DSM rotates even this small file and still signals all
`sh` processes, the persistent sink should move to a tmpfs diagnostic path or a
DSM-supported per-service logging facility before rollout.

### 4.3 Event policy and rate limits

| Event | Logging behavior |
| --- | --- |
| Initial mode/network/port/disk state | One record at startup |
| IP, carrier, gateway reachability, TCP/5000, or disk topology transition | One record per actual transition |
| Ping RTT or refresh timestamp changes | No persistent log record |
| Console unavailable/write failure | Log first failure; repeat at most once per 5 minutes, with a suppressed-count summary when recovery occurs |
| KMS setup failure | Log first failure; retry with 1, 2, 4, 8, then 30-second backoff; log recovery and periodic summaries, not every retry |
| KMS mode/connector change | One record per change |
| Beep result | One result record for the single melody attempt |
| Logger/rotation failure | One record if possible; do not recurse into stderr logging |

KMS retry backoff must not stop discovery of a DRM card which appears late.
Once a KMS display is active, the existing one-time initialization and
framebuffer diagnostics remain available through the bounded logger.

## 5. Compatibility and scope

- Preserve current screen layout, live field updates, and two-second cadence.
- Preserve the helper's HUP-ignore behavior; do not try to intercept or repair
  DSM's global `pkill` command.
- Preserve Junior reason detection, DSM 7 service staging, and DSM 6 skip
  behavior.
- Keep the log filename and normal startup/transition diagnostics unless the
  pilot proves DSM still rotates a sub-megabyte file.
- Do not alter Joplin's image, command, restart policy, or Docker configuration
  in this addon change.
- Implementation is confined to the tcrp-addons helper. Any recipe digest or
  loader packaging hashes affected by changed addon payloads must be updated in
  that implementation change.

## 6. Verification plan

### Local deterministic tests

1. Feed the shell monitor a stable state with a changing RTT for at least
   10,000 simulated probe cycles. Confirm the status file and display data
   continue changing while no RTT-only diagnostic records are written.
2. Change each normalized field individually. Confirm exactly one transition
   record per change and no duplicates while the state stays stable.
3. Simulate a missing console and repeated KMS setup errors. Confirm retries
   continue with the specified backoff, logs remain rate-limited, and the status
   monitor remains alive.
4. Rename the log while a test process is running. Confirm the next event opens
   the current pathname and the old rotated inode stops growing.
5. Exercise the logger cap repeatedly and confirm the total retained data stays
   at or below the configured limit.
6. Retain the isolated Docker regression test: a test-only `tini -> supervisor
   -> sh` tree receives HUP only inside its own PID namespace; confirm the
   supervisor exit and Docker restart policy. Never run broad `pkill` on the
   host or on a production NAS.

### DSM pilot

1. Build a pilot addon and record SHA-256 values for `selftest.sh`,
   `kms-display`, and all changed recipe payloads.
2. Install only on a designated DSM 7.4 test system with a non-production
   Joplin instance or other disposable shell-based test container.
3. Observe at least 48 hours without manually invoking `synologrotated`,
   forcing rotation, or sending signals. Record helper log size, inode/FD
   targets, `/var/log/messages`, `logrotate.status`, Docker events, and the
   helper's display update behavior.
4. Acceptance requires: unchanged two-second screen updates; helper diagnostics
   stay within the cap; no helper-triggered emergency-rotation records; no
   unrelated container exits; and recovery from a transient KMS/console error.
5. Do not deploy broadly until the exact pilot hashes and logs are reviewed.

## 7. Remaining uncertainties

- The deleted 102 MB log prevents determining which high-rate source dominated.
- The exact size threshold and internal decision path for DSM emergency
  rotation have not been recovered from Synology source or a controlled DSM
  instrumentation run.
- The `pkill` parent PID/argv was not captured; DSM rotation is the strongly
  supported caller, not a directly recorded process-parent chain.
- The incident helper script hash is known, but no published addon tag was
  proven to contain that exact payload set.

These uncertainties do not change the design's primary safety rule: live
screen refresh is not a diagnostic event and must never be written to the
persistent log on every probe.

## 8. Implementation status

The helper now routes diagnostics through a mode-0600 FIFO and one short-lived
logger worker. The worker opens and closes the named log for each record,
maintains a 256 KiB active file and two 256 KiB plain-text rotations, and exits
when its owning monitor exits. Screen refresh and RTT-only changes are excluded
from state logging. Console write failures are limited to one record per five
minutes with a recovery summary. KMS discovery/setup retries use 1, 2, 4, 8,
then 30-second delays and report the first failure, periodic summaries, and
recovery. Junior and DSM launch wrappers no longer append the monitor's full
stdout/stderr lifetime to the DSM log.

Local validation was performed in Docker Desktop with a static x86-64 build.
The isolated logger test confirmed that writing resumes at the current path
after an external rename, the FIFO is mode 0600, each retained log stays at or
below 256 KiB, and a missing FIFO reader does not block a log sender. The
The initial DSM 7.4.1-90080 smoke pilot is running. The helper service stayed
active; KMS reported the VMware `VIRTUAL-1` connector at 1280x800; the status
refresh advanced by two seconds while gateway ping, TCP/5000, and three disks
were populated. The preexisting helper log was about 10 MiB and was preserved
before startup; after startup, the active file was 1,368 bytes, `.1` was exactly
256 KiB, and `.2` was empty. The log size did not change during a subsequent
30-second observation, and no helper process held the persistent log open. No
Docker containers were running before or after the helper update. The 48-hour
passive observation and direct visual inspection of the monitor remain pending;
no forced rotation or global signal was used.
