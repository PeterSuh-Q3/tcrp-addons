# Junior Realtime Helper (SA6400 pilot)

The addon starts an early monitor at the `on_patches` hook and stages a DSM-side
monitor from `on_os_load` into `/tmpRoot`. DSM 7+ receives an enabled systemd
service. DSM 6 remains registered and uses the early monitor; only its DSM-stage
service is skipped. That second-stage launcher keeps the IPv4, gateway ping,
TCP/5000, disk, and display refresh fields live after DSM takes over. It writes observations to
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
The panel uses a compact, color-coded layout similar to the FRIEND boot
summary: model/DSM identity, GPU, CPU/thread count, DMI, device counts, boot
mode, and NIC details appear first. The full `/proc/cmdline` is shown directly
under the network rows. The original self-test results remain grouped at the
bottom: current IP, gateway ping response, DSM TCP/5000 readiness (reported as
`NOT READY` when the selected NIC has no carrier), recognized disk count, and
disk rows. The text fallback follows the same top-summary and bottom-self-test
order.

Because the helper sets a KMS mode and keeps its scanout buffer alive, stop it
only as part of shutting down/restarting the junior environment. A reboot or
DRM driver reinitialization restores the display state. The panel shows model,
serial and MAC from the kernel command line; DSM product/build/update and
platform from `VERSION`; CPU and thread count; DMI identity; UEFI/legacy mode;
PCI HBA/NIC/GPU counts; NIC IPv4, driver and PCI IDs; and SATA/other and NVMe
counts with up to eight disk rows. It identifies the loader P3 through
`/dev/synoboot3` and its filesystem UUID, then omits the matching physical
disk's P3 from the count and list. Other kernel-visible disks may include
devices that are not usable for DSM installation.

TCP readiness means that the local service answered an HTTP connection; it
does not confirm DSM installation. The same universal recipe is registered for
all 52 platform and DSM build combinations used by the repository's other
universal addons, including DSM 6. The late hook skips DSM service installation
on DSM 6. The shell monitor and static x86-64 DRM helper use generic
Linux interfaces; DRM/KMS drawing is attempted when a compatible display is
available, with virtual-console output as a fallback. Live hardware validation
has been performed on the SA6400 / DSM 7.4.1 pilot, not on every registered
combination. The loader must explicitly include this addon; registration alone does not
change normal loader builds. The DSM-stage startup handoff is staged through
`/tmpRoot` at `on_os_load`; live validation is being performed on the SA6400
DSM 7.4.1 pilot.

To rebuild the binary, use `src/build-kms-display.sh` with an x86-64 Linux
static GCC and DRM UAPI headers (for example, the matching DSM toolkit headers
through `DRM_INCLUDE`).
