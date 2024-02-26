. /usr/syno/share/environments.sh
. /usr/syno/share/rootdevice.sh

SynoRbdModule="/lib/modules/synofsbd.ko"
SynoFsbdModule="/lib/modules/synorbd.ko"
Sha256Module="/lib/modules/sha256_generic.ko"
LibSha256Module="/lib/modules/libsha256.ko"
SynoRbdRootDevice="/dev/synorbd_system"
SystemRootDevice="/dev/system-root"
BrmFlag="/enable_brm"

LoadBrmModules()
{
	if [ -e "${SynoRbdModule}" ]; then
		echo "Insert synorbd kernel module"
		insmod "${SynoRbdModule}"
	fi
	if [ -e "${SynoFsbdModule}" ]; then
		echo "Insert synofsbd kernel module"
		insmod "${SynoFsbdModule}"
	fi
	if [ -e "${LibSha256Module}" ]; then
		echo "Insert libsha256 kernel module"
		insmod "${LibSha256Module}"
	fi
	if [ -e "${Sha256Module}" ]; then
		echo "Insert sha256 kernel module"
		insmod "${Sha256Module}"
	fi
}

# 0: enabled, 255: disabled
IsEnableBrm()
{
    if [ -f "${BrmFlag}" ]; then
        return 0;
    fi
    return 255;
}

LoadSynoRbd()
{
    if [ "$SupportSynoRbdVspace" != "yes" ]; then
        return
    fi
	if /usr/syno/bin/synostgcore --is-rbd-valid "$RootDevice" ; then
		if /usr/syno/bin/synostgcore --load-rbd-space "$RootDevice"; then
			/bin/touch $BrmFlag
			echo "load $(GetRootDevice) on $RootDevice"
			RootDevice=$(GetRootDevice)
		else
			echo "failed to load rbd device"
		fi
	fi
}

UnloadSynoRbd()
{
    if [ -b "$SynoRbdRootDevice" ]; then
        /usr/syno/bin/synostgcore --unload-rbd-space "$SynoRbdRootDevice"
        if [ -L $SystemRootDevice ]; then
            Rm $SystemRootDevice
        fi
        Rm $BrmFlag
        RootDevice=$(GetRootDevice)
        . /usr/syno/share/dsmupdate/decide_system_partition.sh
    fi
}
