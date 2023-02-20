#!/usr/bin/env ash


### USUALLY SCEMD is the last process run in init, so when scemd is running we are most
# probably certain that system has finish init process
#

# Detect correct file
HW_REVISION=`cat /proc/sys/kernel/syno_hw_revision`
[ -n "${HW_REVISION}" ] && DTBFILE="model_${HW_REVISION}.dtb" || DTBFILE="model.dtb"
[ -e /etc.defaults/${DTBFILE} ] || DTBFILE="model.dtb"

if [ `mount | grep tmpRoot | wc -l` -gt 0 ] ; then
  HASBOOTED="yes"
  echo "System passed junior"
else
  echo "System is booting"
  HASBOOTED="no"
fi


if [ "$HASBOOTED" = "no" ]; then

  echo "dtbpatch - early"
  # fix executable flag
  cp dtbpatch /usr/sbin/
  cp dtc /usr/sbin/
  chmod +x /usr/sbin/dtbpatch
  chmod +x /usr/sbin/dtc

  echo "Patching /etc.defaults/${DTBFILE}"

  # Dynamic generation fabio
  if dtbpatch /etc.defaults/${DTBFILE} /var/run/model.dtb; then
    cp -vf /var/run/model.dtb /etc.defaults/${DTBFILE}
  else
    echo "Error patching dtb"
  fi

  # Dynamic generation pocopico
#  /usr/sbin/dtbpatch /etc.defaults/model.dtb output.dtb
#  if [ $? -ne 0 ]; then
#    echo "Error patching dtb"
#  else
#    cp -vf output.dtb /etc.defaults/model.dtb
#    cp -vf output.dtb /var/run/model.dtb
#    /usr/sbin/dtc -I dtb -O dts /etc.defaults/model.dtb > /etc.defaults/model.dts
#  fi

elif [ "$HASBOOTED" = "yes" ]; then
  echo "dtbpatch - late"
  
  echo "Copying /etc.defaults/${DTBFILE}"
  
  # copy utilities 
  cp -f /usr/sbin/dtbpatch /tmpRoot/usr/sbin
  cp -f /usr/sbin/dtc /tmpRoot/usr/bin
  
  # copy file fabio
  cp -vf /etc.defaults/${DTBFILE} /tmpRoot/etc.defaults/model.dtb  
  
  # copy file pocopico
  #cp -vf /etc.defaults/model.dtb /tmpRoot/etc.defaults/model.dtb
  #cp -vf /etc.defaults/model.dtb /var/run/model.dtb
fi
