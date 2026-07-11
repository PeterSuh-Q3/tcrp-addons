#!/bin/sh

set -o pipefail 

PLATFORM="$(uname -a | awk '{print $NF}' | cut -d '_' -f2)"

SED_PATH='/tmpRoot/usr/bin/sed'
XXD_PATH='/tmpRoot/usr/bin/xxd'
LSPCI_PATH='/tmpRoot/usr/bin/lspci'

fixcpufreq() {

    if [ $(mount 2>/dev/null | grep sysfs | wc -l) -eq 0 ]; then
        mount -t sysfs sysfs /sys
        [ -f /tmpRoot/usr/lib/modules/processor.ko ] && insmod /tmpRoot/usr/lib/modules/processor.ko
        [ -f /tmpRoot/usr/lib/modules/acpi-cpufreq.ko ] && insmod /tmpRoot/usr/lib/modules/acpi-cpufreq.ko
    fi
    # CPU performance scaling
    if [ -f /tmpRoot/usr/lib/modules-load.d/70-cpufreq-kernel.conf ]; then
        cpufreq=$(ls -ltr /sys/devices/system/cpu/cpufreq/* 2>/dev/null | wc -l)
        if [ $cpufreq -eq 0 ]; then
            echo "CPU does NOT support CPU Performance Scaling, disabling"
            ${SED_PATH} -i 's/^acpi-cpufreq/# acpi-cpufreq/g' /tmpRoot/usr/lib/modules-load.d/70-cpufreq-kernel.conf
        else
            echo "CPU supports CPU Performance Scaling, enabling"
            ${SED_PATH} -i 's/^# acpi-cpufreq/acpi-cpufreq/g' /tmpRoot/usr/lib/modules-load.d/70-cpufreq-kernel.conf
        fi
    fi
    umount /sys
}

fixcrypto() {
    # crc32c-intel
    if [ -f /tmpRoot/usr/lib/modules-load.d/70-crypto-kernel.conf ]; then
        CPUFLAGS=$(cat /proc/cpuinfo | grep flags | grep sse4_2 | wc -l)
        if [ $CPUFLAGS -gt 0 ]; then
            echo "CPU Supports SSE4.2, crc32c-intel should load"
        else
            echo "CPU does NOT support SSE4.2, crc32c-intel will not load, disabling"
            ${SED_PATH} -i 's/^crc32c-intel/# crc32c-intel/g' /tmpRoot/usr/lib/modules-load.d/70-crypto-kernel.conf
        fi
    fi

    # aesni-intel
    if [ -f /tmpRoot/usr/lib/modules-load.d/70-crypto-kernel.conf ]; then
        CPUFLAGS=$(cat /proc/cpuinfo | grep flags | grep aes | wc -l)
        if [ ${CPUFLAGS} -gt 0 ]; then
            echo "CPU Supports AES, aesni-intel should load"
        else
            echo "CPU does NOT support AES, aesni-intel will not load, disabling"
            ${SED_PATH} -i 's/support_aesni_intel="yes"/support_aesni_intel="no"/' /tmpRoot/etc.defaults/synoinfo.conf
            ${SED_PATH} -i 's/^aesni-intel/# aesni-intel/g' /tmpRoot/usr/lib/modules-load.d/70-crypto-kernel.conf
        fi
    fi
}

fixnvidia() {
    # Nvidia GPU
    if [ -f /tmpRoot/usr/lib/modules-load.d/70-syno-nvidia-gpu.conf ]; then
        NVIDIADEV=$(cat /proc/bus/pci/devices 2>/dev/null | grep -i 10de | wc -l)
        if [ $NVIDIADEV -eq 0 ]; then
            echo "NVIDIA GPU is not detected, disabling "
            ${SED_PATH} -i 's/^nvidia/# nvidia/g' /tmpRoot/usr/lib/modules-load.d/70-syno-nvidia-gpu.conf
            ${SED_PATH} -i 's/^nvidia-uvm/# nvidia-uvm/g' /tmpRoot/usr/lib/modules-load.d/70-syno-nvidia-gpu.conf
        else
            echo "NVIDIA GPU is detected, nothing to do"
        fi
    fi
}

fixintelgpu() {
  # Intel GPU
  echo "replace intel gpu info for i915le10th"

  # 커널 5.10.55 는 fixintelgpu 처리 대상 아님 — 건너뜀
  # (커널 버전 추출 방식은 all-modules install.sh 와 동일)
  LINUX_VER="$(uname -r | cut -d '+' -f1)"
  if [ "${LINUX_VER}" = "5.10.55" ]; then
    echo "kernel ${LINUX_VER} detected, skipping fixintelgpu"
    return 0
  fi

  GPU="$(lspci -nd ::300 2>/dev/null | grep 8086 | cut -d' ' -f3 | sed 's/://g')"
  grep -iq "${GPU}" "/usr/sbin/i915ids" 2>/dev/null || GPU=""
  if [ -z "${GPU}" ] || [ $(echo -n "${GPU}" | wc -c) -ne 8 ]; then
    echo "GPU is not detected"
    return 0
  fi

  KO_FILE="/usr/lib/modules/i915.ko"
  if [ ! -f "${KO_FILE}" ]; then
    echo "i915.ko does not exist"
    return 0
  fi

  # MSHELL 서명(MSHELL@PeterSuh-Q3) 이 있는 OOT i915 는 GPU ID 를 네이티브 지원하므로
  # binary patch 자체가 불필요 — 패치 건너뜀
  # (modprobe 는 all-modules 에서 이미 수행됨 — 중복 처리 불필요)
  if grep -qa "MSHELL@PeterSuh-Q3" "${KO_FILE}" 2>/dev/null; then
    echo "MSHELL-signed i915.ko detected, skipping binary patch"
    return 0
  fi

  isLoad=0
  if lsmod 2>/dev/null | grep -q "^i915"; then
    isLoad=1
    echo "removing i915 ..." 
    /usr/sbin/modprobe -r i915
  fi
  GPU_DEF="86800000923e0000"
  GPU_BIN="${GPU:2:2}${GPU:0:2}0000${GPU:6:2}${GPU:4:2}0000"
  echo "GPU:${GPU} GPU_BIN:${GPU_BIN}"
  cp -pf "${KO_FILE}" "${KO_FILE}.tmp"
  if xxd -c $(xxd -p "${KO_FILE}.tmp" 2>/dev/null | wc -c) -p "${KO_FILE}.tmp" 2>/dev/null |
    sed "s/${GPU_DEF}/${GPU_BIN}/; s/308201f706092a86.*70656e6465647e0a//" |
    xxd -r -p >"${KO_FILE}" 2>/dev/null; then
    echo "i915 xxd proc success!!!" 
  else  
    echo "i915 xxd proc fail!!!" 
  fi  
  rm -vf "${KO_FILE}.tmp"
  #if [ "${isLoad}" = "1" ]; then
    echo "doing modprobe i915 ..." 
    /usr/sbin/modprobe i915
  #fi
  
}

copyintelgpu() {
  KO_FILE="/tmpRoot/usr/lib/modules/i915.ko"
  [ ! -f "${KO_FILE}.bak" ] && cp -vf "${KO_FILE}" "${KO_FILE}.bak"
  cp -vf "/usr/lib/modules/i915.ko" "${KO_FILE}"
}

fixacpibutton() {
    #button.ko

    if [ ! -d /proc/acpi ]; then
        echo "NO ACPI status is available, disabling button.ko"
        ${SED_PATH} -i 's/^button/# button/g' /tmpRoot/usr/lib/modules-load.d/70-video-kernel.conf
    fi

}

fixservice() {
  # service
  # systemd-modules-load SynoInitEth syno-oob-check-status syno_update_disk_logs
  rm -vf /tmpRoot/usr/lib/modules-load.d/70-network*.conf
  SERVICE_PATH="/tmpRoot/usr/lib/systemd/system"
  ${SED_PATH} -i 's|ExecStart=/|ExecStart=-/|g' ${SERVICE_PATH}/systemd-modules-load.service
  ${SED_PATH} -i 's|ExecStart=/|ExecStart=-/|g' ${SERVICE_PATH}/syno-oob-check-status.service 
  ${SED_PATH} -i 's|ExecStart=/|ExecStart=-/|g' ${SERVICE_PATH}/SynoInitEth.service 
  ${SED_PATH} -i 's|ExecStart=/|ExecStart=-/|g' ${SERVICE_PATH}/syno_update_disk_logs.service
}

fixsdcard() {
  # sdcard
  [ ! -f /tmpRoot/usr/lib/udev/script/sdcard.sh.bak ] && cp -vpf /tmpRoot/usr/lib/udev/script/sdcard.sh /tmpRoot/usr/lib/udev/script/sdcard.sh.bak
  printf '#!/bin/sh\nexit 0\n' >/tmpRoot/usr/lib/udev/script/sdcard.sh
}

fixamdgpu() {
  # AMDGPU 모듈 강제 로더 systemd unit 생성.
  # /exts/custom-modules 디렉토리가 존재할 때만 활성.
  # custom-modules 는 일반 모듈 팩 형식이라 coldplug 트리거가 보장되지 않을 수 있어
  # 명시적 modprobe 가 필요.
  # 오류 발생 시에도 부팅 전체를 망치지 않도록 모든 단계에 || true 를 둔다.
  if [ -d /exts/custom-modules ]; then
    DEST="/tmpRoot/usr/lib/systemd/system/mshell-amdgpu.service"
    {
      echo "[Unit]"
      echo "Description=MSHELL AMDGPU Module Loader"
      echo "After=local-fs.target"
      echo "Before=pkgctl.target"
      echo
      echo "[Service]"
      echo "Type=oneshot"
      echo "ExecStart=/bin/sh -c '/sbin/depmod -a && /sbin/modprobe amdgpu'"
      echo "RemainAfterExit=yes"
      echo
      echo "[Install]"
      echo "WantedBy=multi-user.target"
    } > "${DEST}" 2>/dev/null || true
    chmod 644 "${DEST}" 2>/dev/null || true
    mkdir -p /tmpRoot/usr/lib/systemd/system/multi-user.target.wants 2>/dev/null || true
    ln -sf /usr/lib/systemd/system/mshell-amdgpu.service \
           /tmpRoot/usr/lib/systemd/system/multi-user.target.wants/mshell-amdgpu.service 2>/dev/null || true
    echo "mshell-amdgpu.service installed (custom-modules detected)"
  fi

  return 0
}

fixnetwork() {
  # network
  if grep -q 'network.' /proc/cmdline; then
    for I in $(grep -Eo 'network.[0-9a-fA-F:]{12,17}=[^ ]*' /proc/cmdline); do
      MACR="$(echo "${I}" | cut -d. -f2 | cut -d= -f1 | sed 's/://g; s/.*/\L&/')"
      IPRS="$(echo "${I}" | cut -d= -f2)"
      for F in /sys/class/net/eth*; do
        [ ! -e "${F}" ] && continue
        ETH="$(basename "${F}")"
        MACX=$(cat "/sys/class/net/${ETH}/address" 2>/dev/null | sed 's/://g; s/.*/\L&/')
        if [ "${MACR}" = "${MACX}" ]; then
          echo "Setting IP for ${ETH} to ${IPRS}"
          F="/etc/sysconfig/network-scripts/ifcfg-${ETH}"
          /bin/set_key_value "${F}" "BOOTPROTO" "static"
          /bin/set_key_value "${F}" "ONBOOT" "yes"
          /bin/set_key_value "${F}" "IPADDR" "$(echo "${IPRS}" | cut -d/ -f1)"
          /bin/set_key_value "${F}" "NETMASK" "$(echo "${IPRS}" | cut -d/ -f2)"
          /bin/set_key_value "${F}" "GATEWAY" "$(echo "${IPRS}" | cut -d/ -f3)"
          /etc/rc.network restart ${ETH} >/dev/null 2>&1
          [ -n "$(echo "${IPRS}" | cut -d/ -f4)" ] && /etc/rc.network_routing "$(echo "${IPRS}" | cut -d/ -f4)" &
        fi
      done
    done
  fi  
}

if [ "${1}" = "patches" ]; then
    echo "Installing addon misc - ${1}"

    if [ -d /exts/all-modules ]; then
        cp -vf /exts/misc/i915ids /usr/sbin/i915ids
        chmod +x /usr/sbin/i915ids
        fixintelgpu
    fi
    
    fixnetwork

elif [ "${1}" = "late" ]; then
    echo "Installing addon misc - ${1}"
    echo "Script for fixing missing HW features dependencies"

    #cp -vf /exts/misc/sed /tmpRoot/usr/bin/sed
    #chmod +x /tmpRoot/usr/bin/sed

    # [single] epyc7003ntb(PAS7700): 설치된 시스템(/tmpRoot)을 standalone 으로 만든다.
    # PAS7700 은 FSDN 이중 컨트롤러 모델이라, 설치된 DSM 이 IsFSDN=yes 로 부팅하면
    # synoconfstored(핵심 설정 데몬)/AA 클러스터/ntb_brd 등 HA 서비스가 실제 NTB/공유
    # 스토리지를 요구하다 실패 루프에 빠져 웹 UI 가 안 뜬다(가짜 하드웨어라 HA 불가).
    # IsFSDN 을 결정하는 권위 게이트는 syno_feature_check.sh 의 SYNO_PRODUCT_FSDN
    # (하드코딩, synoinfo.conf 무시)이므로, 설치 결과물에서 이 줄을 제거해 IsFSDN=no
    # (standalone) 로 부팅하게 한다. junior ramdisk 쪽은 ramdisk-004 패치가 담당.
    if [ "${PLATFORM}" = "epyc7003ntb" ]; then
        FCHK="/tmpRoot/usr/syno/sbin/syno_feature_check.sh"
        if [ -f "${FCHK}" ] && grep -q "^SYNO_PRODUCT_FSDN$" "${FCHK}"; then
            cp -pf "${FCHK}" "${FCHK}.bak" 2>/dev/null
            sed -i '/^SYNO_PRODUCT_FSDN$/d' "${FCHK}"
            echo "[single] disabled SYNO_PRODUCT_FSDN in installed system -> IsFSDN=no (standalone)"
        fi
    fi

    # [single] epyc7003ntb: synoconfstored/AA 서버가 바인딩할 ntb_eth0 로컬 IP 를 부팅 초기에 제공.
    # PAS7700 의 synoconfstored/api_runner/distributed_lock 은 컨트롤러 IP(169.254.4.1 또는 .2,
    # hb_interface_name=ntb_eth0)에 소켓을 바인딩하는데, 실 NTB 하드웨어가 없어 ntb_eth0(ntb_netdev)
    # 가 안 생기면 "Invalid local IP []" 로 크래시 루프 → DSM 전체 사용 불가.
    # eth0 위 VLAN 으로 ntb_eth0 를 만들고 hardware_info 의 is_controller0 에 맞는 IP 를 할당하는
    # 부팅 서비스를 설치해, synoconfstored 시작 전에 바인딩 대상을 확보한다.
    # (실기 45.26 VM 에서 synoconfstored 정상 기동 검증됨. AA 는 피어 부재 degraded 로 동작)
    if [ "${PLATFORM}" = "epyc7003ntb" ]; then
        NTBSCR="/tmpRoot/usr/syno/lib/systemd/scripts/mshell-ntb-eth0.sh"
        cat > "${NTBSCR}" <<'NEOF'
#!/bin/sh
# MSHELL single-node AA(degraded): provide ntb_eth0 local IP so synoconfstored/AA
# servers can bind. Real ntb_netdev has no hardware here; use a VLAN on eth0.
HWINFO=/usr/syno/etc/synoaa/conf/hardware_info
IP=169.254.4.2
grep -q '"is_controller0":true' "$HWINFO" 2>/dev/null && IP=169.254.4.1
if ! /sbin/ip link show ntb_eth0 >/dev/null 2>&1; then
  /sbin/modprobe 8021q 2>/dev/null
  /sbin/ip link add link eth0 name ntb_eth0 type vlan id 100 2>/dev/null
fi
/sbin/ip addr show ntb_eth0 2>/dev/null | grep -q "$IP" || /sbin/ip addr add ${IP}/24 dev ntb_eth0
/sbin/ip link set ntb_eth0 up
exit 0
NEOF
        chmod +x "${NTBSCR}"
        cat > "/tmpRoot/usr/lib/systemd/system/mshell-ntb-eth0.service" <<'NEOF'
[Unit]
Description=MSHELL fake ntb_eth0 for single-node AA (degraded)
DefaultDependencies=no
After=syno-kernel-modules-load.service
Before=synoconfstoreeventd.service synoconfstored.service sysinit.target
[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/syno/lib/systemd/scripts/mshell-ntb-eth0.sh
[Install]
WantedBy=sysinit.target
NEOF
        mkdir -p /tmpRoot/usr/lib/systemd/system/sysinit.target.wants
        ln -sf ../mshell-ntb-eth0.service /tmpRoot/usr/lib/systemd/system/sysinit.target.wants/mshell-ntb-eth0.service
        echo "[single] installed mshell-ntb-eth0 service (ntb_eth0 local IP for synoconfstored)"
    fi

    fixacpibutton

    if [ -d /exts/all-modules ]; then    
        copyintelgpu
        case "${PLATFORM}" in
        denverton)
            fixnvidia
            ;;
        esac
    else
        fixamdgpu        
    fi    

    fixcpufreq
    fixcrypto
    fixsdcard
    fixservice

  # packages
  if [ ! -f /tmpRoot/usr/syno/etc/packages/feeds ]; then
    mkdir -p /tmpRoot/usr/syno/etc/packages
    echo '[{"feed":"https://spk7.imnks.com","name":"imnks"},{"feed":"https://packages.synocommunity.com","name":"synocommunity"}]' >/tmpRoot/usr/syno/etc/packages/feeds
  fi    
fi
