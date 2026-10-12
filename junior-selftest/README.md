# Junior self-test display (SA6400 pilot)

This addon runs only in the DSM junior ramdisk, at the `on_patches` hook. It
shows the current IPv4 address, local TCP/5000 readiness, and the count and
list of kernel-visible disks on the active Linux virtual console (normally
`tty1`). It writes observations to `/var/log/junior-selftest.log`. It does not
install DSM, mount a disk, or modify partitions.

Character output uses the virtual console TTY and does not require a
framebuffer device. The panel reserves the top 14 console rows and is redrawn
every ten seconds because DSM may repaint the screen. The disk count includes
all detected SATA/SCSI/NVMe/virtio block devices and can include the loader
disk; it is not a count of disks proven usable for DSM installation.

TCP readiness means that the local service answered an HTTP connection; it
does not confirm DSM installation. The recipe is scoped to
`epyc7002_74_51055`; the SA6400 DSM 7.4.1 loader must explicitly include this
addon. Merely adding this directory does not change normal loader builds.
