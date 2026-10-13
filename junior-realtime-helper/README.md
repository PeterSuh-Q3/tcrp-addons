# Junior Realtime Helper (SA6400 pilot)

The addon starts at `on_jrExit` when `/var/log/junior_reason` records either
`Exit on error [12]` together with `go to junior mode`, or
`Exit on error [7]` together with `root not matched with junior` (the model
migration case). The hook also runs for other linuxrc exits, so this reason
check limits startup to these junior fallback states.
The monitor checks for `/linuxrc.syno` before starting and on every refresh,
then asks the KMS helper to restore the previous display when it exits. No DSM
system service is installed. It displays the build-time LKM, module-pack,
module-type and loader-version snapshots from `/addons`, along with IPv4,
gateway ping, TCP/5000, disk, and refresh status during junior mode. It writes
observations to
`/var/log/junior-realtime-helper.log`. It does not install DSM, mount a disk,
or modify partitions.

The bundled static x86-64 `kms-display` helper searches `/dev/dri/card*` for a
connected DRM display, preferring a connector that is already active. It does
not assume HDMI or a particular GPU, so DRM-backed HDMI, DisplayPort, VGA, and
virtual displays can work. The helper owns DRM master and redraws the panel
every two seconds while the junior monitor runs. A visible local-time stamp
shows the last refresh to the second. It does not need `/dev/fb0`,
fbcon, or a virtual console. If DRM/KMS is unavailable, the shell monitor
continues to print to the active virtual console when one exists.
The panel uses a color-coded layout similar to the FRIEND boot summary. Each
identity field is displayed on its own line, followed by separate `LKM`,
`tcrp-modules`, `Module Type`, and `Loader version` rows immediately above
`PLATFORM`. Hardware, device-count, network, and self-test fields also use one
line per item. The full `/proc/cmdline` follows the network rows and wraps over
additional lines when needed. The original self-test results remain grouped at
the bottom: current IP, gateway ping response, DSM TCP/5000 readiness (reported
as `NOT READY` when the selected NIC has no carrier), recognized disk count,
disk rows, and the two-second refresh time. The text fallback follows the same
one-field-per-line order.
The KMS panel also identifies the selected connector (for example `HDMI-A-1`)
and reports its connection state and active output resolution. This comes from
the DRM connector and mode selected by the renderer, so it applies to i915,
amdgpu, and other DRM/KMS drivers without a GPU-specific backlight module.

When the monitor exits, it asks the KMS helper to restore the CRTC and
framebuffer that were active before the panel took over, then waits for that
cleanup to finish. If another DRM client has already taken control, restoration
may fail; a driver reinitialization or reboot then resets the display. The panel
shows model, serial and MAC from the kernel command line; DSM product/build/update and
platform from `VERSION`; CPU and thread count; DMI identity; UEFI/legacy mode;
PCI HBA/NIC/GPU counts; NIC IPv4, driver and PCI IDs; and SATA/other and NVMe
counts with up to eight disk rows. It identifies the loader P3 through
`/dev/synoboot3` and its filesystem UUID, then omits the matching physical
disk's P3 from the count and list. Other kernel-visible disks may include
devices that are not usable for DSM installation.

TCP readiness means that the local service answered an HTTP connection; it
does not confirm DSM installation. The same universal recipe is registered for
all 52 platform and DSM build combinations used by the repository's other
universal addons, including DSM 6. The shell monitor and static x86-64 DRM
helper use generic Linux interfaces; DRM/KMS drawing is attempted when a
compatible display is available, with virtual-console output as a fallback.
Live hardware validation
has been performed on the SA6400 / DSM 7.4.1 pilot, not on every registered
combination. The loader must explicitly include this addon; registration alone
does not change normal loader builds. The helper is intentionally limited to
junior mode; normal DSM boot is outside its scope.

MSHELL Manager can disable the hook for the next loader build by adding the
kernel argument `junior-realtime-helper=0`. The hook checks `/proc/cmdline`
before inspecting the junior fallback reason or starting the monitor. If the
argument is absent, the addon's historical enabled-by-default behavior is
preserved. Changing the Manager setting requires rebuilding and rebooting the
loader; it does not stop a helper that is already running.

To rebuild the binary, use `src/build-kms-display.sh` with an x86-64 Linux
static GCC and DRM UAPI headers (for example, the matching DSM toolkit headers
through `DRM_INCLUDE`).
