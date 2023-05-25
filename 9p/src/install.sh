#!/bin/bash
#
# install 9p virtio tcrp modules
#

function getvars() {
TARGET_PLATFORM="$(uname -u | cut -d '_' -f2)"
LINUX_VER="$(uname -r | cut -d '+' -f1)"
}

function install() {
echo "Copying kmod to /bin/"
/bin/cp -v kmod  /bin/       ; chmod 700 /bin/kmod
echo "link depmod,modprobe to kmod"
[ ! -f /usr/sbin/depmod ] && ln -s /bin/kmod /usr/sbin/depmod
[ ! -f /usr/sbin/modprobe ] && ln -s /bin/kmod /usr/sbin/modprobe
tar xvfz /exts/tcrp-9p/${TARGET_PLATFORM}-${LINUX_VER}.tgz -C /
mv -f /root/usr/lib/modules/9p*.ko /usr/lib/modules
echo "Loading 9p module"
/usr/sbin/depmod -a
/usr/sbin/modprobe 9p
/usr/sbin/modprobe 9pnet_virtio
}

getvars
install
