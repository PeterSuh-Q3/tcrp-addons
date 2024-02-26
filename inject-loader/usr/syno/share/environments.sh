#!/bin/sh
# shellcheck disable=SC2034 # convenient variables may not be used

GetKV() { /bin/get_key_value "$@"; }
Mkdir() { /bin/mkdir "$@"; }
Rmdir() { /bin/rmdir "$@"; }
Mount() { /bin/mount "$@"; }
Umount() { /bin/umount "$@"; }
Tar() { /bin/tar "$@"; }
Mv() { /bin/mv "$@"; }
Cp() { /bin/cp "$@"; }
Rm() { /bin/rm "$@"; }
Ln() { /bin/ln "$@"; }
Ls() { /bin/ls "$@"; }
Ps() { /bin/ps "$@"; }
Dmesg() { /bin/dmesg "$@"; }
Seq() { /bin/seq "$@"; }
Cat() { /bin/cat "$@"; }
Cut() { /bin/cut "$@"; }
Echo() { /bin/echo "$@"; }
Grep() { /bin/grep "$@"; }

SYNOINFO_DEF="/etc.defaults/synoinfo.conf"

UniqueRD=$(GetKV "${SYNOINFO_DEF}" unique | Cut -d_ -f2)
UniqueModel=$(GetKV "${SYNOINFO_DEF}" unique | Cut -d_ -f3)
SupportRAID=$(GetKV "${SYNOINFO_DEF}" supportraid)
SupportPortMappingV2=$(GetKV "${SYNOINFO_DEF}" supportportmappingv2)
SupportAutoInstall=$(GetKV "${SYNOINFO_DEF}" support_auto_install)
DiskSwap=$(GetKV "${SYNOINFO_DEF}" disk_swap)
IsAliDSM=$(GetKV "${SYNOINFO_DEF}" ali_dsm)
SupportSynoRbdVspace=$(GetKV "${SYNOINFO_DEF}" support_synorbd_vspace)
SupportEmmcBoot=$(GetKV "${SYNOINFO_DEF}" support_emmc_boot)

if [ "$UniqueRD" = "broadwellntb" ] || [ "$UniqueRD" = "broadwellntbap" ]; then
	IsUCOrXA="yes"
fi
