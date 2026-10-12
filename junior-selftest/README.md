# Junior self-test display (SA6400 pilot)

This addon runs only in the DSM junior ramdisk, at the `on_patches` hook. It
shows the current IPv4 address, local TCP/5000 readiness, and kernel-visible
block devices on the local framebuffer. It writes the same observations to
`/tmp/junior-selftest.log`. It does not install DSM, mount a disk, or modify
partitions. The screen output is ASCII and limited to the first three disks;
the log lists every detected disk. `/tmp` is volatile.

The renderer is a static x86-64 Linux binary. Rebuild it with `sh build-fb.sh`
and update the three SHA-256 values in `recipes/universal.json` before using a
modified package. The recipe is scoped to `epyc7002_74_51055`; the SA6400
DSM 7.4.1 loader must explicitly include this addon. Merely adding this
directory does not change normal loader builds.

The renderer requires `/dev/fb0` with packed RGB565 or 32-bit RGB pixels and
at least 320×160 resolution. It does not take over a virtual console. If the
framebuffer is unavailable or unsupported, monitoring continues in the log.
The panel is redrawn every ten seconds because DSM may repaint the screen.
Display visibility and persistence must be checked on physical hardware.

TCP readiness means that the local service answered an HTTP connection; it
does not confirm DSM installation. The disk count includes kernel-visible
devices and may include the loader itself, so it is not a count of usable
DSM installation disks.
