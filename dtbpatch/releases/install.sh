#!/usr/bin/env ash

### USUALLY SCEMD is the last process run in init, so when scemd is running we are most
# probably certain that system has finish init process
#

if [ `mount | grep tmpRoot | wc -l` -gt 0 ] ; then
  HASBOOTED="yes"
  echo "System passed junior"
else
  echo "System is booting"
  HASBOOTED="no"
fi

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
  cp -fv /etc.defaults/model.dtb /run/model.dtb
  /usr/syno/bin/syno_slot_mapping
}

if [ "$HASBOOTED" = "no" ]; then

  echo "dtbpatch - early"
  # fix executable flag
  cp dtc /usr/sbin/
  chmod +x /usr/sbin/dtc

  echo "Patching /etc.defaults/${DTBFILE}"
  MODEL="$(uname -u)"
  # Dynamic generation arc
  dtModel $MODEL

elif [ "$HASBOOTED" = "yes" ]; then
  echo "dtbpatch - late"
  
  echo "Copying /etc.defaults/${DTBFILE}"
  
  # copy dtb file
  cp -vf /etc.defaults/model.dtb /tmpRoot/etc.defaults/model.dtb
  cp -fv /etc.defaults/model.dtb /tmpRoot/run/model.dtb
  /usr/syno/bin/syno_slot_mapping
fi
