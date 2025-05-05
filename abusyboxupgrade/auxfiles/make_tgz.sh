tar -zcvf usr.tgz ./usr/* && sha256sum usr.tgz
cd "5.10.55" && tar -zcvf ../btrfs_5.10_ko.tgz ./lib/modules/* && sha256sum ../btrfs_5.10_ko.tgz
cd "../4.4.302" && tar -zcvf ../btrfs_4.4_ko.tgz ./lib/modules/* && sha256sum ../btrfs_4.4_ko.tgz
