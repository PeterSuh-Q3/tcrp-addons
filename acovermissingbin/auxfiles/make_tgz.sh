find ./usr -name '.DS_Store' -delete
chmod +x ./usr/sbin/*
chmod +x ./usr/bin/*
tar -zchf usr.tgz ./usr/
sha256sum usr.tgz
#tar -zcvf usr6.tgz ./usr/* && sha256sum usr6.tgz
