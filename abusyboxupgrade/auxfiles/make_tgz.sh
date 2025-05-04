tar -zcvf usr.tgz ./usr/* && sha256sum usr.tgz
tar -zcvf btrfs_ko.tgz ./lib/modules/* && sha256sum btrfs_ko.tgz
