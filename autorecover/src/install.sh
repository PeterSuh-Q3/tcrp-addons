#!/usr/bin/env ash

#
# Copyright (C) 2024-2026 PeterSuh-Q3
# https://github.com/PeterSuh-Q3
#
# This installer script is licensed under the
# PeterSuh-Q3 Non-Commercial Source-Available License.
#
# The kernel module installed by this script is a separate component
# distributed under its applicable GPL-compatible license.
#
KVER_CLEAN=$(uname -r | sed -n 's/^\([0-9]\+\.[0-9]\+\.[0-9]\+\).*/\1/p')
ZPADKVER=$(printf "%01d%03d%03d\n" $(echo "$KVER_CLEAN" | tr '.' ' '))

write_grub_saved_entry_zero() {
  grubenv="$1"
  tmp="${grubenv}.tmp.$$"
  size=$(wc -c < "$grubenv" 2>/dev/null | tr -d ' ')

  # GRUB environment blocks are fixed-size files. Refuse to rewrite an
  # unexpected format or size rather than risking corruption of the boot env.
  if [ "$size" -ne 1024 ] || [ "$(head -n 1 "$grubenv")" != "# GRUB Environment Block" ]; then
    echo "autorecover: cannot safely update unexpected grubenv format; leaving it unchanged"
    return 1
  fi

  if ! awk 'NR == 1 { print; next } /^#/ { next } /^saved_entry=/ { next } NF { print }' "$grubenv" > "$tmp"; then
    rm -f "$tmp"
    return 1
  fi
  echo "saved_entry=0" >> "$tmp"

  size=$(wc -c < "$tmp" 2>/dev/null | tr -d ' ')
  if [ "$size" -gt 1024 ]; then
    rm -f "$tmp"
    echo "autorecover: grubenv content exceeds its fixed-size block; leaving it unchanged"
    return 1
  fi
  pad=$((1024 - size))
  if [ "$pad" -gt 0 ]; then
    dd if=/dev/zero bs=1 count="$pad" 2>/dev/null | tr '\000' '#' >> "$tmp" || {
      rm -f "$tmp"
      return 1
    }
  fi

  if [ "$(wc -c < "$tmp" | tr -d ' ')" -ne 1024 ] || ! grep -q '^saved_entry=0$' "$tmp"; then
    rm -f "$tmp"
    echo "autorecover: failed to validate the rewritten grubenv; leaving it unchanged"
    return 1
  fi

  if mv -f "$tmp" "$grubenv"; then
    echo "autorecover: reset grubenv saved_entry to 0"
    return 0
  fi
  rm -f "$tmp"
  return 1
}

reset_reinstall_grub_default() {
  p1=/mnt/p1
  p1_mounted_here=0
  p1_loop=0
  mkdir -p "$p1"

  if ! mount | grep -q " on ${p1} "; then
    # Match the existing autorecover mount decision: a symlinked synoboot1
    # uses /.bootdisk/.p1, while a block node is mounted through loop.
    file_type=$(ls -l /dev/synoboot1 2>/dev/null | cut -c 1)
    if [ "$file_type" = "b" ]; then
      if [ -f /lib/modules/loop.ko ] && [ "$(lsmod | grep -c loop)" -eq 0 ]; then
        modprobe loop || true
      fi
      losetup /dev/loop1 /dev/synoboot1 || return 1
      p1_loop=1
      mount -t vfat /dev/loop1 "$p1" || {
        losetup -d /dev/loop1 2>/dev/null || true
        return 1
      }
    else
      [ -r /.bootdisk ] && [ -r /.p1 ] || return 1
      bootdisk=$(cat /.bootdisk)
      p1num=$(cat /.p1)
      mount -t vfat "${bootdisk}${p1num}" "$p1" || return 1
    fi
    p1_mounted_here=1
  fi

  release_p1_mount() {
    if [ "$p1_mounted_here" -eq 1 ] && umount "$p1"; then
      p1_mounted_here=0
      [ "$p1_loop" -eq 1 ] && losetup -d /dev/loop1 2>/dev/null || true
    fi
  }

  grub_cfg="$p1/boot/grub/grub.cfg"
  grubenv="$p1/boot/grub/grubenv"
  if [ ! -r "$grub_cfg" ]; then
    echo "autorecover: GRUB config not found on P1; default unchanged"
    release_p1_mount
    return 1
  fi

  cfg_default=$(sed -n 's/^[[:space:]]*set default="\([0-9][0-9]*\)".*/\1/p' "$grub_cfg" | head -n 1)
  saved_entry=""
  if [ -f "$grubenv" ]; then
    saved_entry=$(sed -n 's/^saved_entry=\([0-9][0-9]*\)$/\1/p' "$grubenv" | tail -n 1)
  fi
  effective_default="${saved_entry:-$cfg_default}"

  if [ "$effective_default" != "3" ]; then
    echo "autorecover: effective GRUB default is ${effective_default:-unknown}, not reinstall entry 3"
  else
    if [ -n "$saved_entry" ] && ! write_grub_saved_entry_zero "$grubenv"; then
      echo "autorecover: saved default is 3 but grubenv reset failed; leaving GRUB config unchanged"
      release_p1_mount
      return 1
    fi

    if [ "$cfg_default" = "3" ]; then
      sed -i 's/^[[:space:]]*set default="3"[[:space:]]*$/set default="0"/' "$grub_cfg" || {
        echo "autorecover: failed to reset grub.cfg default"
        release_p1_mount
        return 1
      }
    fi
    sync
    echo "autorecover: reset DSM reinstall boot default from entry 3 to entry 0"
  fi

  release_p1_mount
}

if [ "${1}" = "rcExit" ]; then
  echo "autorecover - ${1}"

  # DSM Re-Install is GRUB entry 3. Reset it on rcExit only when it is
  # currently the effective default, so the next reboot returns to entry 0.
  # This is independent of smallfix recovery and does not depend on JOT.
  reset_reinstall_grub_default || echo "autorecover: GRUB default check/reset was not completed"

  if [ $(cat /var/log/junior_reason | grep "error \[7\]" | wc -l) -gt 0 ]; then

    if [ "$ZPADKVER" -gt 4004059 ] && ! grep -q smallfixnumber /var/log/linuxrc.syno.log; then
      echo "It's not smallfixnumber difference condition. exit now!!!"
      exit 0
    fi
  
    echo "smallfixnumber difference detected. Automatic patching is performed. !!!"
    echo "Copy the rd.gz and zImage files from /tmpRoot where /dev/md0 is mounted."

    mkdir -p /mnt/p1
    mkdir -p /mnt/p2    
    cd /dev

    file_type=$(ls -l /dev/synoboot1 | cut -c 1)

    if [ "$file_type" == "b" ]; then
      if [ -f /lib/modules/loop.ko ] && [ $(lsmod | grep -c loop) -eq 0 ]; then
          echo "Loading loop module..."
          modprobe loop || echo "Module load attempt completed"
          ls -l /dev/loop* 2>/dev/null || echo "No loop devices found, exit now!"
          [ $(ls /dev/loop* 2>/dev/null | wc -l) -eq 0 ] && exit 0
      fi
      # use loop device for safe mount
      losetup /dev/loop1 /dev/synoboot1
      losetup /dev/loop2 /dev/synoboot2
      mount -t vfat /dev/loop1 /mnt/p1
      mount -t vfat /dev/loop2 /mnt/p2
    else
      BOOTDISK=$(cat /.bootdisk)
      echo "BOOTDISK is ${BOOTDISK}"
      P1=$(cat /.p1)
      P2=$(cat /.p2)
      mount -t vfat ${BOOTDISK}${P1} /mnt/p1
      mount -t vfat ${BOOTDISK}${P2} /mnt/p2
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
        echo "The copy process is complete, Reboot Now..."
        reboot
      fi
    fi
    
  fi
fi
