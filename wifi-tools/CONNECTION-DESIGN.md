# Wi-Fi connection reliability design

Status: proposed; the current implementation is described in README.md. This
document does not claim that the changes below have been implemented or tested.

## Scope and constraints

Improve WPA2-Personal connection in DSM junior, using the existing rcExit
worker and the current `user_config.json` and `/addons/mshell-wifi.conf` build
flow. Drivers and firmware remain separately supplied. Do not change the normal
DSM networking setup as part of the junior implementation. The RR wireless
addon demonstrates explicit DHCP after starting a supplicant, but its DSM
`synonet --dhcp` command must not be assumed to work in junior.

## Proposed state machine

1. Validate configuration and bundled runtime, record startup and discover a
   wireless interface via `phy80211`, with bounded waiting and a configurable
   or deterministic selection policy when multiple devices are present.
2. Check the interface, driver binding and relevant firmware errors. Identify
   existing supplicant ownership using a live PID and its actual interface;
   do not kill or replace processes owned by another network manager.
3. Bring the selected interface up and start `wpa_supplicant` with a control
   socket. Bundle `wpa_cli` with matching libraries and notices; use it to
   observe `wpa_state=COMPLETED`, not merely daemon startup. Distinguish
   timeout, explicit authentication rejection and unavailable diagnostics.
4. After association, inspect whether a DHCP client or DSM network manager is
   already responsible for this interface. If not, invoke an available junior
   DHCP client scoped to that interface, with bounded retry and logging. Exact
   commands and ownership checks require verification on the target junior OS.
   Do not start competing clients or disrupt existing wired addresses, DNS,
   default routes or active sessions. Record any network policy changes.
5. Confirm a non-link-local IPv4 address and record route state separately;
   an address alone does not prove gateway, DNS, or Internet reachability.
   Report timeout as failure, rather than returning success with no address.

Do not pass credentials via kernel command line or process arguments. Keep
configuration and derived PSK protected; do not copy them to diagnostics.
Logs can still contain sensitive SSIDs, MAC addresses, IPs or other data:
minimize collection, redact secrets and verify redaction against test cases.

## Diagnostics and recovery

Record stage, elapsed time, interface and a distinct reason such as
`NO_CONFIG`, `NO_INTERFACE`, `DRIVER_OR_FIRMWARE_ERROR`,
`SUPPLICANT_START_FAILED`, `AUTH_TIMEOUT`, `DHCP_UNAVAILABLE`, `DHCP_TIMEOUT`
or `CONNECTED`. An inference from logs must not be presented as a confirmed
driver or authentication failure. Persist early and final diagnostics to the
existing loader P3 / `WIFILOG` paths where available, retaining a `/run` copy
and logging write failures. Ensure background execution does not suppress the
only evidence of an early failure. Avoid stale locks and PID files; clean up
only processes and resources owned by this worker.

## Implementation and verification plan

- Update `build-wifi-tools.sh` to include `wpa_cli`, audit binary dependencies,
  rebuild archives, and update checksums, metadata and third-party notices as
  appropriate. Update `wifi-connect.sh` and `install.sh` without changing the
  existing configuration format.
- Add repeatable tests with mocked commands for missing config/interface,
  stale PID and locks, pre-existing supplicant/DHCP ownership, authentication
  failure and timeout, DHCP unavailable/timeout, successful address assignment,
  multiple interfaces, and credential redaction.
- On junior hardware verify correct credentials and DHCP, wrong password,
  absent AP, authenticated association without DHCP, existing wired connectivity,
  and behavior when another network manager already owns the interface.
  Verify both persistent diagnostic destinations and missing-storage fallback.
- Separately investigate normal DSM startup and `synonet --dhcp` before any
  DSM-stage implementation; do not assume junior results apply to DSM.

Reference: [RR wireless addon](https://github.com/syno-community/rr-addons/blob/main/wireless/all/usr/bin/wireless_supplicant.sh).
