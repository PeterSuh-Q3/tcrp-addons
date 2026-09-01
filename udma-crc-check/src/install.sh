#!/usr/bin/env ash

if [ "${1}" = "late" ]; then
  echo "udma-crc-check - ${1}"
  echo "Installing udma-crc-check scripts and service"
  
  cp -vf check_udma_crc.sh /tmpRoot/usr/sbin/check_udma_crc.sh
  chmod 755 /tmpRoot/usr/sbin/check_udma_crc.sh

  # systemd loads /etc/systemd/system/<unit> in preference to
  # /usr/lib/systemd/system/<unit> of the same name. This addon lived
  # in /etc/systemd/system until 2025-09-02; an old install can still
  # have a leftover copy there that permanently shadows the current
  # /usr/lib/systemd/system unit below (confirmed alongside the same
  # issue in the hdddb addon). Remove it before writing our own copy.
  if [ -f "/tmpRoot/etc/systemd/system/udma-crc-check.service" ]; then
    echo "Removing stale /etc/systemd/system/udma-crc-check.service override from an earlier loader"
    rm -f "/tmpRoot/etc/systemd/system/udma-crc-check.service"
  fi
  if [ -f "/tmpRoot/etc/systemd/system/udma-crc-check.timer" ]; then
    echo "Removing stale /etc/systemd/system/udma-crc-check.timer override from an earlier loader"
    rm -f "/tmpRoot/etc/systemd/system/udma-crc-check.timer"
  fi

  cp -vf udma-crc-check.service /tmpRoot/usr/lib/systemd/system/udma-crc-check.service
  cp -vf udma-crc-check.timer /tmpRoot/usr/lib/systemd/system/udma-crc-check.timer
  cp -vf udma-check.env /tmpRoot/etc/udma-check.env

  # 디렉토리 생성 (존재하지 않을 경우)
  mkdir -p /tmpRoot/usr/lib/systemd/system/timers.target.wants
  
  # 심볼릭 링크 생성 (수동 enable)
  ln -sf /usr/lib/systemd/system/udma-crc-check.timer /tmpRoot/usr/lib/systemd/system/timers.target.wants/udma-crc-check.timer

  # 서비스 파일 권한 설정
  chmod 644 /tmpRoot/usr/lib/systemd/system/udma-crc-check.service
  chmod 644 /tmpRoot/usr/lib/systemd/system/udma-crc-check.timer
  # 환경변수 파일 보안 설정
  chmod 600 /tmpRoot/etc/udma-check.env

  echo "udma-crc-check Installation completed "
fi
