#!/bin/sh

patch_installer_sh() {
  installer_file="/usr/syno/sbin/installer.sh"
  installer_temp="${installer_file}.$$"

  if [ ! -f "${installer_file}" ]; then
    return 0
  fi

  if grep -q "FORMATFIX_BEGIN" "${installer_file}"; then
    echo "installer.sh already patched"
    return 0
  fi

  if ! grep -q 'DoOrExit CREATE Raidtool initsys "$FormatAllArg"' "${installer_file}"; then
    echo "target Raidtool initsys line not found, skip"
    return 0
  fi

  awk '
    /InitRAIDSysDisks \(\)/ && inserted == 0 {
      print "###########################################################"
      print "# FORMATFIX_BEGIN"
      print "FormatfixIsLoaderDisk ()"
      print "{"
      print "\tlocal disk=\"$1\""
      print "\tlocal dev label"
      print "\tfor dev in /dev/${disk}[0-9]* /dev/${disk}p[0-9]*; do"
      print "\t\t[ -e \"$dev\" ] || continue"
      print "\t\tlabel=$(blkid -s LABEL -o value \"$dev\" 2>/dev/null)"
      print "\t\tcase \"$label\" in"
      print "\t\t\tRR1|RR2|RR3) return 0 ;;"
      print "\t\tesac"
      print "\tdone"
      print "\treturn 1"
      print "}"
      print ""
      print "FormatfixGetInstallableDisks ()"
      print "{"
      print "\tlocal disks=\"${InstallableDisks:-}\""
      print "\tlocal disk seen=\"\""
      print "\tdisks=\"$disks $(/usr/syno/bin/synostgcore --installable-disk-list 2>/dev/null)\""
      print "\tfor disk in /sys/block/sata* /sys/block/sd* /sys/block/nvme*n* /sys/block/hd* /sys/block/vd* /sys/block/xvd*; do"
      print "\t\t[ -e \"$disk\" ] && disks=\"$disks ${disk##*/}\""
      print "\tdone"
      print "\tfor disk in $disks; do"
      print "\t\tcase \"$disk\" in"
      print "\t\t\tram*|loop*|md*|dm-*|sr*|synoboot*) continue ;;"
      print "\t\tesac"
      print "\t\t[ -e \"/sys/block/${disk}\" ] || continue"
      print "\t\t[ -e \"/dev/${disk}\" ] || continue"
      print "\t\tFormatfixIsLoaderDisk \"$disk\" && continue"
      print "\t\tcase \" $seen \" in"
      print "\t\t\t*\" $disk \"*) continue ;;"
      print "\t\tesac"
      print "\t\tseen=\"$seen $disk\""
      print "\t\t/bin/echo \"$disk\""
      print "\tdone"
      print "}"
      print ""
      print "FormatfixPartDevice ()"
      print "{"
      print "\tcase \"$1\" in"
      print "\t\t*[0-9]) /bin/echo \"${1}p${2}\" ;;"
      print "\t\t*) /bin/echo \"${1}${2}\" ;;"
      print "\tesac"
      print "}"
      print ""
      print "FormatfixWaitPartDevice ()"
      print "{"
      print "\tlocal dev=\"$1\""
      print "\tlocal i=0"
      print "\twhile [ $i -lt 10 ]; do"
      print "\t\t[ -e \"$dev\" ] && return 0"
      print "\t\tsleep 1"
      print "\t\ti=$((i + 1))"
      print "\tdone"
      print "\treturn 1"
      print "}"
      print ""
      print "FormatfixInitFSDNSysDisks ()"
      print "{"
      print "\tEcho \"FormatfixInitFSDNSysDisks\""
      print "\tlocal PARTNO_ROOT_TAIPEI=\"1\""
      print "\tlocal PARTNO_PATCH=\"2\""
      print "\tlocal WRITEABLE_SIZE=6291456"
      print "\tlocal PATCH_SIZE=3145728"
      print "\tlocal PATCH_SKIP=0"
      print "\tlocal disks DiskIdx Device Devices num PartDevice"
      print ""
      print "\tdisks=$(FormatfixGetInstallableDisks)"
      print "\tEcho \"formatfix disks: $disks\""
      print "\t[ -n \"$disks\" ] || return 1"
      print ""
      print "\t/sbin/mdadm -S /dev/md0"
      print "\tfor DiskIdx in $disks ; do"
      print "\t\tDevice=/dev/${DiskIdx}"
      print "\t\tDoOrExit FDISK Sfdisk -M1 ${Device}"
      print "\t\tDoOrExit CLEAN Sfdisk \"--fast-delete\" \"-1\" \"${Device}\""
      print "\t\tDoOrExit CREATE CreatePartition ${PARTNO_ROOT_TAIPEI} ${WRITEABLE_SIZE} ${LINUX_RAID_TYPE} ${ROOT_SKIP} ${Device}"
      print "\t\tDoOrExit CREATE CreatePartition ${PARTNO_PATCH} ${PATCH_SIZE} ${LINUX_FS_TYPE} ${PATCH_SKIP} ${Device}"
      print "\tdone"
      print ""
      print "\tDevices=\"\""
      print "\tfor DiskIdx in $disks ; do"
      print "\t\tPartDevice=$(FormatfixPartDevice \"/dev/${DiskIdx}\" \"${PARTNO_ROOT_TAIPEI}\")"
      print "\t\tFormatfixWaitPartDevice \"$PartDevice\" && Devices=\"$Devices $PartDevice\""
      print "\tdone"
      print "\tnum=$(Echo $Devices | /bin/wc -w)"
      print "\t[ \"$num\" -gt 0 ] || return 1"
      print "\t/sbin/mdadm -C /dev/md0 -e 0.9 -amd -R -l1 --force -n$num $Devices"
      print ""
      print "\tfor DiskIdx in $disks ; do"
      print "\t\tPartDevice=$(FormatfixPartDevice \"/dev/${DiskIdx}\" \"${PARTNO_PATCH}\")"
      print "\t\tFormatfixWaitPartDevice \"$PartDevice\" && DoOrExit MKFS MakeSystemFS \"$PartDevice\""
      print "\tdone"
      print "}"
      print "# FORMATFIX_END"
      print "###########################################################"
      print ""
      inserted = 1
    }
    /^[[:space:]]*DoOrExit CREATE Raidtool initsys "\$FormatAllArg"[[:space:]]*$/ {
      print "\t\tif [ \"$SynoProduct\" = \"FSDN\" ] || [ \"$UniqueRD\" = \"epyc7003ntb\" ] || [ \"$UniqueRD\" = \"epyc7003ntbap\" ]; then"
      print "\t\t\tDoOrExit CREATE FormatfixInitFSDNSysDisks"
      print "\t\telse"
      print "\t\t\tDoOrExit CREATE Raidtool initsys \"$FormatAllArg\""
      print "\t\tfi"
      replaced = 1
      next
    }
    { print }
    END {
      if (inserted != 1 || replaced != 1) {
        exit 1
      }
    }
  ' "${installer_file}" >"${installer_temp}" || {
    rm -f "${installer_temp}"
    echo "failed to patch installer.sh"
    return 1
  }

  mv -f "${installer_temp}" "${installer_file}"
  chmod +x "${installer_file}"
  echo "installer.sh patched"
}

patch_assemble_system_raid_sh() {
  assemble_file="/usr/syno/share/assemble_system_raid.sh"
  assemble_temp="${assemble_file}.$$"

  if [ ! -f "${assemble_file}" ]; then
    return 0
  fi

  if grep -q "FORMATFIX_ASSEMBLE_V1" "${assemble_file}"; then
    echo "assemble_system_raid.sh already patched"
    return 0
  fi

  if ! grep -q 'GetSortedExistingInstallableDevices 1 \\' "${assemble_file}"; then
    echo "target assemble line not found, skip"
    return 0
  fi

  awk '
    /if \[ ! -d \/sys\/block\/md0 \] && ShouldAssembleMd0InJunior; then/ && inserted == 0 {
      print "# FORMATFIX_ASSEMBLE_V1"
      print "FormatfixAssembleIsLoaderDisk()"
      print "{"
      print "\tlocal disk=\"$1\""
      print "\tlocal dev label"
      print "\tfor dev in /dev/${disk}[0-9]* /dev/${disk}p[0-9]*; do"
      print "\t\t[ -e \"$dev\" ] || continue"
      print "\t\tlabel=$(blkid -s LABEL -o value \"$dev\" 2>/dev/null)"
      print "\t\tcase \"$label\" in"
      print "\t\t\tRR1|RR2|RR3) return 0 ;;"
      print "\t\tesac"
      print "\tdone"
      print "\treturn 1"
      print "}"
      print ""
      print "FormatfixAssemblePartDevice()"
      print "{"
      print "\tcase \"$1\" in"
      print "\t\t*[0-9]) echo \"${1}p${2}\" ;;"
      print "\t\t*) echo \"${1}${2}\" ;;"
      print "\tesac"
      print "}"
      print ""
      print "FormatfixGetRaidParts()"
      print "{"
      print "\tlocal partno=\"$1\""
      print "\tlocal disks disk part seen=\"\""
      print "\tdisks=\"$(/usr/syno/bin/synostgcore --installable-disk-list 2>/dev/null)\""
      print "\tfor disk in /sys/block/sata* /sys/block/sd* /sys/block/nvme*n* /sys/block/hd* /sys/block/vd* /sys/block/xvd*; do"
      print "\t\t[ -e \"$disk\" ] && disks=\"$disks ${disk##*/}\""
      print "\tdone"
      print "\tfor disk in $disks; do"
      print "\t\tcase \"$disk\" in"
      print "\t\t\tram*|loop*|md*|dm-*|sr*|synoboot*) continue ;;"
      print "\t\tesac"
      print "\t\t[ -e \"/sys/block/${disk}\" ] || continue"
      print "\t\t[ -e \"/dev/${disk}\" ] || continue"
      print "\t\tFormatfixAssembleIsLoaderDisk \"$disk\" && continue"
      print "\t\tcase \" $seen \" in"
      print "\t\t\t*\" $disk \"*) continue ;;"
      print "\t\tesac"
      print "\t\tseen=\"$seen $disk\""
      print "\t\tpart=$(FormatfixAssemblePartDevice \"/dev/${disk}\" \"$partno\")"
      print "\t\t[ -e \"$part\" ] && echo \"$part\""
      print "\tdone"
      print "}"
      print ""
      inserted = 1
    }
    /^[[:space:]]*GetSortedExistingInstallableDevices 1 \\/ {
      print "\tFormatfixGetRaidParts 1 \\"
      replaced = 1
      next
    }
    { print }
    END {
      if (inserted != 1 || replaced != 1) {
        exit 1
      }
    }
  ' "${assemble_file}" >"${assemble_temp}" || {
    rm -f "${assemble_temp}"
    echo "failed to patch assemble_system_raid.sh"
    return 1
  }

  mv -f "${assemble_temp}" "${assemble_file}"
  chmod +x "${assemble_file}"
  echo "assemble_system_raid.sh patched"
}

if [ "${1}" = "early" ]; then
  echo "Installing addon misc - ${1}"

  # PAS7700(epyc7003ntb) 전용: 듀얼링크 U.2 없이 일반 NVMe/SATA로 설치 가능하게 우회.
  # 정품 installer.sh/assemble_system_raid.sh 는 synostgcore --installable-disk-list
  # (정품 듀얼링크 U.2 백플레인 인식 API)에 의존해 디스크를 못 찾으면
  # "[CREATE][failed] Raidtool initsys" 로 설치가 멈춘다.
  # RROrg(wjz304)의 misc addon 을 참고해 Raidtool initsys / GetSortedExistingInstallableDevices
  # 호출부를 /sys/block/sata*|sd*|nvme*n*|hd*|vd*|xvd* 전수 스캔 기반의
  # 자체 파티션/RAID1 조립 루틴(FormatfixInitFSDNSysDisks/FormatfixGetRaidParts)으로 치환한다.
  # 다른 플랫폼에 영향 없도록 UNIQUE 값으로 엄격히 게이트.
  UNIQUE="$(/bin/get_key_value /etc.defaults/synoinfo.conf unique 2>/dev/null)"
  if [ "${UNIQUE:-}" = "synology_epyc7003ntb_pas7700" ]; then
    # [CREATE][failed] Raidtool initsys 관련: scemd 의 mdadm 슈퍼블록 버전 인자를
    # "-e 0.9" -> "-e 1.2" 로 이진 패치 (RR 은 전 플랫폼에 무조건 적용하나,
    # 다른 모델에 대한 영향 검증 전까지 PAS7700 로만 스코프를 좁힌다)
    SO_FILE="/usr/syno/bin/scemd"
    [ ! -f "${SO_FILE}.bak" ] && cp -pf "${SO_FILE}" "${SO_FILE}.bak"
    cp -pf "${SO_FILE}" "${SO_FILE}.tmp"
    xxd -c "$(xxd -p "${SO_FILE}.tmp" 2>/dev/null | wc -c)" -p "${SO_FILE}.tmp" 2>/dev/null \
      | sed "s/2d6520302e39/2d6520312e32/" \
      | xxd -r -p >"${SO_FILE}" 2>/dev/null
    rm -f "${SO_FILE}.tmp"

    patch_installer_sh
    patch_assemble_system_raid_sh

    # i2c 하트비트 체커 무력화: 이 박스에는 실제 i2c-4 microP 하드웨어가 없어
    # i2c_hb_checker.sh 가 "/dev/i2c-4 열기 실패" 오류를 도배하므로 진입점만 막는다.
    sed -i 's/^main "\$@"$/# main "\$@"/' "/usr/syno/sbin/i2c_hb_checker.sh" 2>/dev/null || true

    # [single] clusterInstall.sh 를 loopback 으로 우회한다.
    # 단일 노드에는 피어가 없으므로, NTB 피어 IP 를 127.0.0.1(자기 자신)로 돌리고
    # ntb_eth0 인터페이스 인자를 제거하고 check_ntb_connection 을 무력화해
    # 클러스터 설치가 존재하지 않는 피어를 영원히 기다리지 않게 한다.
    sed -i -E 's/169\.254\.4\.(1|2)/127.0.0.1/g; s/ --interface ntb_eth[0-9]{1,2}//g; s/check_ntb_connection$/exit 0 # check_ntb_connection/' /usr/syno/share/clusterInstall.sh 2>/dev/null || true

    # [single] synomulticontroller 래퍼 설치 (피어 없음).
    # 설치 apply 단계(scemd)는 IsFSDN 과 무관하게 synomulticontroller 로
    #   --up_lock_ctrl GET_LOCK ...  (apply-lock) 을 호출하는데, 단일 노드에는
    # 조율할 피어가 없어 원본 바이너리는 잠금을 못 얻고 error_apply_lock
    # ("다른 설치가 진행 중") 으로 설치가 막힌다.
    # 피어/HA 체크는 전부 가짜 성공으로, 그 외(잠금 등)는 exit 0(획득됨)로 처리한다.
    # 단일 노드는 실제 조율 대상이 없으므로 원본 위임(delegate)이 불필요 → 백업/smc_real 없이
    # 항상 가짜 응답하는 단순·견고한 래퍼로 둔다.
    SMC=/usr/syno/bin/synomulticontroller
    cat > "${SMC}" <<'WEOF'
#!/bin/sh
# MSHELL single-node synomulticontroller shim (epyc7003ntb, no peer).
# Callers capture stdout via $(...) and compare exact strings - echo expected text.
for a in "$@"; do
  case "$a" in
    --is_remote_power_on)  echo "Remote controller power is on"; exit 1 ;;
    --location)            echo "location:0"; exit 0 ;;
    --ntb_heartbeat_check) echo "Current link is up"; exit 0 ;;
    --check_chassis_match) echo "Chassis match"; exit 0 ;;
  esac
done
# Everything else (up/apply lock, etc.): no real peer to coordinate with on a
# single node, so treat as success (empty stdout, exit 0) instead of failing.
exit 0
WEOF
    chmod +x "${SMC}"
  fi

elif [ "${1}" = "modules" ]; then
    echo "Install stty bin, Starting ttyd, listening on port: 7681"
    tar -zxvf ./stty.tgz -C /usr/sbin
    tar -zxvf ./lrzsz.tgz -C /usr/sbin
    tar -zxvf ./ttyd.tgz
    ./ttyd login > /dev/null 2>&1 &

elif [ "${1}" = "rcExit" ]; then
  echo "Installing addon misc - ${1}"

  # [single] early 단계의 clusterInstall.sh loopback 이 웹 설치 UI 재시작 등으로
  # 되돌아갈 경우를 대비한 안전망 (단일 노드: 피어 대기 원천 차단).
  UNIQUE="$(/bin/get_key_value /etc.defaults/synoinfo.conf unique 2>/dev/null)"
  if [ "${UNIQUE:-}" = "synology_epyc7003ntb_pas7700" ]; then
    sed -i 's/check_ntb_connection$/exit 0 # check_ntb_connection/' "/usr/syno/share/clusterInstall.sh" 2>/dev/null || true
  fi

  # invalid_disks
  # method 1 # (block dsm system migrate)
  # SH_FILE="/usr/syno/share/get_hcl_invalid_disks.sh"
  # [ -f "${SH_FILE}" ] && cp -pf "${SH_FILE}" "${SH_FILE}.bak" && printf '#!/bin/sh\nexit 0\n' >"${SH_FILE}"
  # method 2
  while true; do [ ! -f "/tmp/installable_check_pass" ] && touch "/tmp/installable_check_pass"; sleep 1; done &  # using a while loop in case DSM is running in a VM

  mkdir -p /usr/syno/web/webman
  # clear system disk space
  cat >/usr/syno/web/webman/clean_system_disk.cgi <<EOF
#!/bin/sh

echo -ne "Content-type: text/plain; charset=\"UTF-8\"\r\n\r\n"
if [ -b /dev/md0 ]; then
  mkdir -p /mnt/md0
  mount /dev/md0 /mnt/md0/
  rm -rf /mnt/md0/@autoupdate/*
  rm -rf /mnt/md0/upd@te/*
  rm -rf /mnt/md0/.log.junior/*
  umount /mnt/md0/
  rm -rf /mnt/md0/
  echo '{"success": true}'
else
  echo '{"success": false}'
fi
EOF
  chmod +x /usr/syno/web/webman/clean_system_disk.cgi

  # get logs
  cat >/usr/syno/web/webman/get_logs.cgi <<EOF
#!/bin/sh

echo -ne "Content-type: text/plain; charset=\"UTF-8\"\r\n\r\n"
echo "==== proc cmdline ===="
cat /proc/cmdline 
echo "==== SynoBoot log ===="
cat /var/log/linuxrc.syno.log
echo "==== Installerlog ===="
cat /tmp/installer_sh.log
echo "==== Messages log ===="
cat /var/log/messages
EOF
  chmod +x /usr/syno/web/webman/get_logs.cgi

  # recovery.cgi
  cat >/usr/syno/web/webman/recovery.cgi <<EOF
#!/bin/sh

echo -ne "Content-type: text/plain; charset=\"UTF-8\"\r\n\r\n"

echo "Starting ttyd ..."
MSG=""
MSG="\${MSG}MSHELL Recovery Mode\n"
MSG="\${MSG}\n"
MSG="\${MSG}Using terminal commands to modify system configs, execute external binary\n"
MSG="\${MSG}files, add files, or install unauthorized third-party apps may lead to system\n"
MSG="\${MSG}damages or unexpected behavior, or cause data loss. Make sure you are aware of\n"
MSG="\${MSG}the consequences of each command and proceed at your own risk.\n"
MSG="\${MSG}\n"
MSG="\${MSG}Warning: Data should only be stored in shared folders. Data stored elsewhere\n"
MSG="\${MSG}may be deleted when the system is updated/restarted.\n"
MSG="\${MSG}\n"
MSG="\${MSG}To 'Force re-install DSM': please visit http://<ip>:5000/web_install.html\n"
MSG="\${MSG}To 'System partition(/dev/md0) has been mounted to': /tmpRoot\n"
echo -e "\${MSG}" > /etc/motd

/usr/bin/killall ttyd 2>/dev/null || true
./ttyd -W -t titleFixed="MSHELL Recovery" login -f root >/dev/null 2>&1 &

cp -pf /usr/syno/web/web_index.html /usr/syno/web/web_install.html
cp -pf web_index.html /usr/syno/web/web_index.html
mkdir -p /tmpRoot
mount /dev/md0 /tmpRoot
echo "Recovery mode is ready"
EOF
  chmod +x /usr/syno/web/webman/recovery.cgi

  # recovery
  if grep -Eq "recovery" /proc/cmdline 2>/dev/null; then
    /usr/syno/web/webman/recovery.cgi
  fi

#usb nic mac spoofing
    #cmdline=$(cat /proc/cmdline)

    #for i in $(seq 1 8); do
    #    val=$(echo "$cmdline" | grep -o -E "mac${i}=[^ ]+" | cut -d= -f2)
    #    if [ -z "$val" ]; then
    #        break
    #    fi
    #    eval "mac${i}=${val}"
    #done
    
    #ethdevs=$(ls /sys/class/net/ | grep -v lo || true)
    #I=1
    #for eth in $ethdevs; do
    #    curmacmask=$(ip link show $eth | awk '/link\/ether/ {print toupper($2)}')
    #    eval "usrmac=\${mac${I}}"
    #    if [ -n "${usrmac}" ] && [ "${usrmac}" != "null" ]; then
    #        if [ "${curmacmask}" != "${usrmac}" ]; then
    #            echo "Setting MAC Address from ${curmacmask} to ${usrmac} on ${eth}" 
    #            ip link set dev ${eth} address ${usrmac} >/dev/null 2>&1 
    #        else
    #            echo "MAC Address on ${eth} is already set to ${usrmac}, skipping"
    #        fi
    #    fi
    #    I=$((I + 1))
    #    if [ "${eth}" = "eth8" ]; then
    #        break
    #    fi
    #done
  ip a    


  SERIAL_DEV="/dev/ttyUSB0"

  # ttyUSB0 생성 대기 (최대 5초)
  for i in $(seq 1 5); do
    [ -c "$SERIAL_DEV" ] && break
    sleep 1
  done

  # 장치 없으면 종료
  if [ ! -c "$SERIAL_DEV" ]; then
    exit 0
  fi

  # 권한 및 baud 설정
  chmod 666 "$SERIAL_DEV"
  stty -F "$SERIAL_DEV" 115200 cs8 -cstopb -parenb -crtscts -ixon -ixoff raw 2>/dev/null

  # 1. messages 최종 내용 먼저 덤프
  if [ -f /var/log/messages ]; then
    echo "===== messages =====" > "$SERIAL_DEV"
    cat /var/log/messages > "$SERIAL_DEV"
    echo "====================" > "$SERIAL_DEV"
  fi

  # 2. linuxrc.syno.log 다음에 덤프
  if [ -f /var/log/linuxrc.syno.log ]; then
    echo "===== linuxrc.syno.log =====" > "$SERIAL_DEV"
    cat /var/log/linuxrc.syno.log > "$SERIAL_DEV"
    echo "============================" > "$SERIAL_DEV"
  fi

  # 3. tail 시작
  echo "===== tail start =====" > "$SERIAL_DEV"
  tail -f /var/log/messages > "$SERIAL_DEV" &
  
fi

#echo "Starting dufs ..."
#/usr/bin/killall dufs 2>/dev/null || true
#/usr/sbin/dufs -A -p 7304 / >/dev/null 2>&1 &
