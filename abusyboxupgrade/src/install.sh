#!/usr/bin/env ash

### USUALLY SCEMD is the last process run in init, so when scemd is running we are most
# probably certain that system has finish init process

if [ "${1}" = "modules" ]; then
  echo "Installing addon abusyboxupgrade - ${1}"
  echo "extract usr-busybox.tgz (busybox 1.35.0) to /usr/sbin/ "
  tar vxfz usr-busybox.tgz -C /usr/sbin/
  mv /usr/sbin/busybox /usr/sbin/busybox135
  echo "make syboliclink for new busybox 1.35.0 "
#  /usr/sbin/busybox135 --install -s /usr/sbin
  for cmd in acpid add-shell addgroup adduser adjtimex ar ascii awk base32 base64 bc blkdiscard blkid bootchartd brctl bunzip2 bzcat bzip2 cal chat chpasswd chpst chrt chvt cksum clear cmp comm conspy cpio crc32 crond crontab cryptpw cttyhack dc deallocvt delgroup deluser depmod devmem dhcprelay diff dos2unix dpkg dpkg-deb dumpkmap dumpleases ed eject envdir envuidgid expand factor fakeidentd fallocate fatattr fbset fdflush fdformat fgconsole fgrep find findfs flash_eraseall flash_lock flash_unlock flashcp flock fold free freeramdisk fsck fsck.minix fsfreeze fstrim fsync ftpd ftpput fuser getopt groups gzip hd hdparm hexdump hexedit hostid hush hwclock i2cdump i2cget i2cset i2ctransfer id ifenslave ifplugd inotifyd install ionice iostat ipaddr ipcrm ipcs iplink ipneigh iproute iprule iptunnel kbd_mode killall5 last less link linux32 linux64 loadfont loadkmap logname losetup lpd lpq lpr lsof lspci lsscsi lsusb lzcat lzma lzop lzopcat makedevs makemime man md5sum mdev mesg microcom mim mkdosfs mke2fs mkfifo mkpasswd mktemp modinfo modprobe mountpoint mpstat mt nameif nbd-client nc nice nl nmeter nohup nologin nproc nsenter ntpd nuke od openvt partprobe passwd paste patch pgrep pidof ping6 pipe_progress pivot_root pkill pmap popmaildir powertop printenv pscan pstree pwdx raidautorun rdate rdev readlink readprofile realpath reformime remove-shell renice reset resume rev rpm rpm2cpio rtcwake run-init run-parts runlevel runsv runsvdir rx script scriptreplay sed sendmail setarch setconsole setfattr setfont setkeycodes setlogcons setsid setuidgid sha1sum sha256sum sha3sum sha512sum showkey shred shuf smemcap softlimit split ssl_client start-stop-daemon stat strings stty su sulogin sum sv svc svlogd svok sysctl tac taskset tc tcpsvd telnet tftp tftpd time timeout tr traceroute traceroute6 truncate ts tty ttysize tunctl tune2fs ubiattach ubidetach ubimkvol ubirename ubirmvol ubirsvol ubiupdatevol udhcpc6 udhcpd udpsvd uevent uncompress unexpand uniq unix2dos unlink unlzma unlzop unshare unzip users usleep uudecode uuencode vconfig vlock volname w wall watch watchdog which who whoami whois xxd
  do
      ln -s /usr/sbin/busybox135 /usr/sbin/$cmd
  done
fi
