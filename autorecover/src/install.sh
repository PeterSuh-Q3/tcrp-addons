#!/usr/bin/env ash

# synoboot
function checkSynoboot() {

    for devtype in $(fdisk -l | grep "Disk /dev/" | cut -c 11-12 ); do

      if [ "${devtype}" = "sd" ]; then
        BOOTDISK="$(blkid | grep "6234-C863" | grep "/dev/${devtype}" | cut -c 6-8 )"
        echo "Found USB or HDD Disk loader!"
      elif [ "${devtype}" = "us" ]; then
        BOOTDISK="$(blkid | grep "6234-C863" | grep "/dev/${devtype}" | cut -c 6-9 )"
        echo "Found USB Disk loader!"
      elif [ "${devtype}" = "sa" ]; then
        BOOTDISK="$(blkid | grep "6234-C863" | grep "/dev/${devtype}" | cut -c 6-10 )"
        echo "Found Sata Disk loader!"
      elif [ "${devtype}" = "nv" ]; then
        BOOTDISK="$(blkid | grep "6234-C863" | grep "/dev/${devtype}" | cut -c 6-12 )"
        echo "Found NVMe Disk loader!"
      elif [ "${devtype}" = "mm" ]; then
        BOOTDISK="$(blkid | grep "6234-C863" | grep "/dev/${devtype}" | cut -c 6-13 )"
        echo "Found MMC Disk loader!"
      else
        BOOTDISK=""
        echo "BOOTDISK value is empty or USB Stick Found!"
        continue
      fi

      if [ $(fdisk -l | grep "83 Linux" | grep "/dev/${BOOTDISK}" | wc -l ) -eq 3 ]; then
        echo "USB Stick or vmdk bootloader disk Found!"
      else
        continue
      fi

      if [ "${devtype}" = "sd" ]; then
        p1="1"
        p2="2"
        p3="3"
      else
        p1="p1"
        p2="p2"
        p3="p3"
      fi
      
    done

}

if [ "${1}" = "rcExit" ]; then
  echo "autorecover - ${1}"
  if [ $(cat /var/log/linuxrc.syno.log | grep smallfixnumber | wc -l) -gt 0 ] && [ $(cat /var/log/junior_reason | grep -e error -e [7] | wc -l) -gt 0 ]; then
    echo "smallfixnumber difference detected. Automatic patching is performed. !!!"
    echo "Copy the rd.gz and zImage files from /tmpRoot where /dev/md0 is mounted."

    mkdir -p /mnt/p1
    mkdir -p /mnt/p2    
    cd /dev

    if [ -b /dev/synoboot1 -a -b /dev/synoboot2 -a -b /dev/synoboot3 ]; then
      mount -t vfat synoboot1 /mnt/p1
      mount -t vfat synoboot2 /mnt/p2
    else
      checkSynoboot
      mount -t vfat ${BOOTDISK}${p1} /mnt/p1
      mount -t vfat ${BOOTDISK}${p2} /mnt/p2
    fi
    
    if [ $( mount | grep /mnt/p2 | wc -l ) -eq 0 ]; then
      echo "Failed to mount /dev/synoboot2 on /mnt/p2 : An error occurred"
      exit 0
    fi
    
    mount_point="/tmpR" # Set the mount point
    device="/dev/md0" # Set the device to be mounted
    wait_time=20 # Set the maximum wait time (in seconds)
    time_counter=0 # Initialize the time counter
    
    # Check if the mount point directory exists, if not, create it
    if [ ! -d "$mount_point" ]; then
      mkdir -p "$mount_point"
    fi
    
    # Try to mount the device on the mount point
    while ! mount "$device" "$mount_point" 2>/dev/null; do
      # If the mount fails because the device or resource is busy
      echo "$?"
      if [ $? -eq 0 ]; then
        sleep 1
        time_counter=$((time_counter+1))
        echo "Device or resource is busy, waiting... ($time_counter of $wait_time seconds)"
        # If the maximum wait time is reached, exit with an error
        if [ $time_counter -ge $wait_time ]; then
          echo "Failed to mount $device on $mount_point: Device or resource is still busy after $wait_time seconds"
          exit 0
        fi
      fi
    done

    if [ $( mount | grep ${mount_point} | wc -l ) -gt 0 ]; then
      # If the mount is successful, print a success message
      echo "$device has been successfully mounted on $mount_point"
      
      cp -vf /tmpR/.syno/patch/rd.gz /mnt/p2
      cp -vf /tmpR/.syno/patch/zImage /mnt/p2
      cp -vf /tmpR/.syno/patch/grub_cksum.syno /mnt/p2
  
      if [ $? -eq 0 ]; then
        [ $(cat /mnt/p1/boot/grub/grub.cfg | grep JOT | wc -l) -gt 0 ] && sed -i "s/set default=\"[0-9]\"/set default=\"0\"/g" /mnt/p1/boot/grub/grub.cfg
        echo "The copy process is complete, Reboot Now..."
        reboot
      fi
    fi
    
  fi
fi
