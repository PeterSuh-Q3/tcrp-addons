#!/usr/bin/env ash

if [ "${1}" = "rcExit" ]; then
  echo "autorecover - ${1}"
  if [ $(cat /var/log/linuxrc.syno.log | grep smallfixnumber | wc -l) -gt 0 ] && [ $(cat /var/log/junior_reason | grep -e error -e [7] | wc -l) -gt 0 ]; then
    echo "smallfixnumber difference detected. Automatic patching is performed. !!!"
    echo "Copy the rd.gz and zImage files from /tmpRoot where /dev/md0 is mounted."

    mkdir -p /mnt/p1
    mkdir -p /mnt/p2    
    cd /dev
    mount -t vfat synoboot1 /mnt/p1
    mount -t vfat synoboot2 /mnt/p2
    
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
          break
        fi
      else
        # If the mount fails for any other reason, exit with an error
        echo "Failed to mount $device on $mount_point: An error occurred"
        break
      fi
    done

    if [ $( mount | grep ${mount_point} | wc -l ) -gt 0 ]; then
      # If the mount is successful, print a success message
      echo "$device has been successfully mounted on $mount_point"
      
      cp -vf /tmpR/.syno/patch/rd.gz /mnt/p2
      cp -vf /tmpR/.syno/patch/zImage /mnt/p2
      cp -vf /tmpR/.syno/patch/grub_cksum.syno /mnt/p2
  
      if [ $? -eq 0 ]; then
        [ $(cat /mnt/p1/boot/grub/grub.cfg | grep JOT | wc -l) -gt 0 ] && sed -i "s/set default=\"[0-9]\"/set default=\"2\"/g" /mnt/p1/boot/grub/grub.cfg
        echo "The copy process is complete, Reboot Now..."
        reboot
      fi
    fi
    
  fi
fi
