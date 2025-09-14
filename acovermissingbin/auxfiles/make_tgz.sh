chmod +x ./usr/sbin/*
tar -zcvf usr.tgz ./usr/* && sha256sum usr.tgz
