#!/usr/bin/env ash

if [ "${1}" = "late" ]; then
  echo "udma-crc-check - ${1}"
  echo "Installing udma-crc-check scripts and service"
  
  cp -vf check_udma_crc.sh /tmpRoot/usr/sbin/check_udma_crc.sh
  chmod 755 /tmpRoot/usr/sbin/check_udma_crc.sh

  cp -vf udma-crc-check.service /tmpRoot/usr/lib/systemd/system/udma-crc-check.service
  cp -vf udma-crc-check.timer /tmpRoot/usr/lib/systemd/system/udma-crc-check.timer
  cp -vf udma-check.env /tmpRoot/etc/udma-check.env

  # 디렉토리 생성 (존재하지 않을 경우)
  mkdir -p /tmpRoot/usr/lib/systemd/system/timers.target.wants
  
  # 심볼릭 링크 생성 (수동 enable)
  ln -vsf /usr/lib/systemd/system/udma-crc-check.timer /tmpRoot/usr/lib/systemd/system/timers.target.wants/udma-crc-check.timer

  # 서비스 파일 권한 설정
  chmod 644 /tmpRoot/usr/lib/systemd/system/udma-crc-check.service
  chmod 644 /tmpRoot/usr/lib/systemd/system/udma-crc-check.timer
  # 환경변수 파일 보안 설정
  chmod 600 /tmpRoot/etc/udma-check.env

  echo "udma-crc-check Installation completed "
fi
