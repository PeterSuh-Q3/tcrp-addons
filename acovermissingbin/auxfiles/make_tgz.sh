rm -f ./usr/sbin/.DS_Store
chmod +x ./usr/sbin/*
tar -zcvf usr.tgz ./usr/* && sha256sum usr.tgz
#tar -zcvf usr6.tgz ./usr/* && sha256sum usr6.tgz
