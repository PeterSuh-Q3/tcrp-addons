#!/usr/bin/env ash

if [ "${1}" = "late" ]; then
  echo "udma-crc-check - ${1}"
  echo "Installing udma-crc-check scripts and service"
  
  cp -vf check_udma_crc.sh /tmpRoot/usr/sbin/check_udma_crc.sh
  chmod 755 /tmpRoot/usr/sbin/check_udma_crc.sh

  cp -vf udma-crc-check.service /tmpRoot/etc/systemd/system/udma-crc-check.service
  cp -vf udma-crc-check.timer /tmpRoot/etc/systemd/system/udma-crc-check.timer
  cp -vf udma-check.env /tmpRoot/etc/udma-check.env

  # 서비스 파일 권한 설정
  chmod 644 /tmpRoot/etc/systemd/system/udma-crc-check.service
  chmod 644 /tmpRoot/etc/systemd/system/udma-crc-check.timer
  # 환경변수 파일 보안 설정
  chmod 600 /tmpRoot/etc/udma-check.env
  
  # systemd 데몬 리로드
  systemctl daemon-reload
  
  # 타이머 활성화 및 시작
  systemctl enable udma-crc-check.timer
  systemctl start udma-crc-check.timer

fi
