#!/usr/bin/env ash

### USUALLY SCEMD is the last process run in init, so when scemd is running we are most
# probably certain that system has finish init process
#

PCI_ER="^[0-9a-fA-F]{4}:[0-9a-fA-F]{2}:[0-9a-fA-F]{2}\.[0-9a-fA-F]{1}"

if [ `mount | grep tmpRoot | wc -l` -gt 0 ] ; then
  HASBOOTED="yes"
  echo "System passed junior"
else
  echo "System is booting"
  HASBOOTED="no"
fi

# USB ports
function getUsbPorts() {
  for I in $(ls -d /sys/bus/usb/devices/usb*); do
    # ROOT
    DCLASS=$(cat ${I}/bDeviceClass)
    [[ ${DCLASS} != "09" ]] && continue
    SPEED=$(cat ${I}/speed)
    [[ ${SPEED} -lt "480" ]] && continue
    RBUS=$(cat ${I}/busnum)
    RCHILDS=$(cat ${I}/maxchild)
    HAVE_CHILD=0
    for C in $(seq 1 ${RCHILDS}); do
      SUB="${RBUS}-${C}"
      if [[ -d ${I}/${SUB} ]]; then
        DCLASS=$(cat ${I}/${SUB}/bDeviceClass)
        [[ ${DCLASS} != "09" ]] && continue
        SPEED=$(cat ${I}/${SUB}/speed)
        [[ ${SPEED} -lt "480" ]] && continue
        CHILDS=$(cat ${I}/${SUB}/maxchild)
        HAVE_CHILD=1
        for N in $(seq 1 ${CHILDS}); do
          echo -n "${RBUS}-${C}.${N} "
        done
      fi
    done
    if [[ ${HAVE_CHILD} = 0 ]]; then
      for N in $(seq 1 ${RCHILDS}); do
        echo -n "${RBUS}-${N} "
      done
    fi
  done
  echo
}

# NVME ports
# 1 - is DT model
function nvmePorts() {
  local NVME_PORTS=$(ls /sys/class/nvme | wc -w)
  for I in $(seq 0 $((${NVME_PORTS}-1))); do
    _PATH=$(readlink /sys/class/nvme/nvme${I} | sed 's|^.*\(pci.*\)|\1|' | cut -d'/' -f2-)
    if [[ ${1} = true ]]; then
      # Device-tree: assemble complete path in DSM format
      DSMPATH=""
      while true; do
        FIRST=$(echo "${_PATH}" | cut -d'/' -f1)
        echo "${FIRST}" | grep -qE "${PCI_ER}" || break
        [[ -z ${DSMPATH} ]] && \
          DSMPATH="$(echo "${FIRST}" | cut -d':' -f2-)" || \
          DSMPATH="${DSMPATH},$(echo "${FIRST}" | cut -d':' -f3)"
        _PATH=$(echo ${_PATH} | cut -d'/' -f2-)
      done
    else
      # Non-dt: just get PCI ID
      DSMPATH=$(echo "${_PATH}" | cut -d'/' -f1)
    fi
    echo -n "${DSMPATH} "
  done
  echo
}

function dtModel() {
  DEST="/var/run/model.dts"
  if [[ ! -f ${DEST} ]]; then  # Users can put their own dts.
    echo "/dts-v1/;"                                                 >${DEST}
    echo "/ {"                                                      >>${DEST}
    echo "    compatible = \"Synology\";"                           >>${DEST}
    echo "    model = \"${1}\";"                                    >>${DEST}
    echo "    version = <0x01>;"                                    >>${DEST}
    # SATA ports
    I=1
    while true; do
      [[ ! -d /sys/block/sata${I} ]] && break
      PCIEPATH=$(grep 'pciepath' /sys/block/sata${I}/device/syno_block_info | cut -d'=' -f2)
      ATAPORT=$(grep 'ata_port_no' /sys/block/sata${I}/device/syno_block_info | cut -d'=' -f2)
      echo "    internal_slot@${I} {"                               >>${DEST}
      echo "        protocol_type = \"sata\";"                      >>${DEST}
      echo "        ahci {"                                         >>${DEST}
      echo "            pcie_root = \"${PCIEPATH}\";"               >>${DEST}
      echo "            ata_port = <0x$(printf '%02X' ${ATAPORT})>;" >>${DEST}
      echo "        };"                                             >>${DEST}
      echo "    };"                                                 >>${DEST}
      I=$((${I}+1))
    done
    
    # NVME ports
    COUNT=1
    for P in $(nvmePorts true); do
      echo "    nvme_slot@${COUNT} {"                               >>${DEST}
      echo "        pcie_root = \"${P}\";"                          >>${DEST}
      echo "        port_type = \"ssdcache\";"                      >>${DEST}
      echo "    };"                                                 >>${DEST}
      COUNT=$((${COUNT}+1))
    done

    # USB ports
    COUNT=1
    for I in $(getUsbPorts); do
      echo "    usb_slot@${COUNT} {"                                >>${DEST}
      echo "      usb2 {"                                           >>${DEST}
      echo "        usb_port =\"${I}\";"                            >>${DEST}
      echo "      };"                                               >>${DEST}
      echo "      usb3 {"                                           >>${DEST}
      echo "        usb_port =\"${I}\";"                            >>${DEST}
      echo "      };"                                               >>${DEST}
      echo "    };"                                                 >>${DEST}
      COUNT=$((${COUNT}+1))
    done
    echo "};"                                                       >>${DEST}
  fi
  cat ${DEST}
  /usr/sbin/dtc -I dts -O dtb ${DEST} >/etc.defaults/model.dtb
  cp -vf /etc.defaults/model.dtb /run/model.dtb
  /usr/syno/bin/syno_slot_mapping
}

if [ "$HASBOOTED" = "no" ]; then

  echo "dtbpatch - early"
  # fix executable flag
  cp -vf dtc /usr/sbin/
  cp -vf readlink /usr/sbin/
  chmod +x /usr/sbin/dtc
  chmod +x /usr/sbin/readlink

  echo "Patching /etc.defaults/${DTBFILE}"
  MODEL="$(uname -u)"
  # Dynamic generation arc
  dtModel $MODEL

elif [ "$HASBOOTED" = "yes" ]; then
  echo "dtbpatch - late"
  
  echo "Copying /etc.defaults/${DTBFILE}"
  
  # copy dtb file
  cp -vf /etc.defaults/model.dtb /tmpRoot/etc.defaults/model.dtb
  cp -vf /etc.defaults/model.dtb /tmpRoot/run/model.dtb

fi
