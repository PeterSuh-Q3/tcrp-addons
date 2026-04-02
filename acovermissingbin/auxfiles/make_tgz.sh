find ./usr -name '.DS_Store' -delete
chmod +x ./usr/bin/*
tar -zchf kmod.tgz ./usr/bin ./usr/sbin/modprobe ./usr/sbin/modinfo ./usr/sbin/depmod
sha256sum kmod.tgz
#tar -zcvf usr6.tgz ./usr/* && sha256sum usr6.tgz
