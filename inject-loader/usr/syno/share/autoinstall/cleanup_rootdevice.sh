#!/bin/sh
# Copyright (c) 2020-2020 Synology Inc. All rights reserved.

. /usr/syno/share/environments.sh
. /usr/syno/share/mkfs.sh
. /usr/syno/share/rootdevice.sh

BackupDirList="
        /var/log
        /.log.junior
"

# In priority order. Path must be under one of BackupDirList
CriticalLogs="
        /var/log/messages
        /var/log/messages.1.xz
        /var/log/messages.2.xz
        /var/log/messages.3.xz
        /var/log/messages.4.xz
        /var/log/messages.5.xz
        /var/log/kern.log
        /var/log/ha.log
        /var/log/scemd.log
        /var/log/rm.log
        /var/log/bash_history.log
        /var/log/bash_err.log
        /var/log/synoinstall.log
        /var/log/synosystemd.log
        /var/log/systemd.log
        /var/log/synoplugin.log
        /var/log/cluster/
        /var/log/synoschedmulti.log
        /var/log/syslog.log
        /var/log/synocrond.log
        /var/log/syno-systemd-status.log
        /var/log/pacemaker.log
        /var/log/ha/
        /var/log/synopkg.log
        /var/log/auth.log
        /var/log/synoscheduler.log
        /var/log/synopkgmgr.log
        /var/log/systemd/
        /var/log/packages/
        /var/log/partition.log
        /var/log/apparmor.log
        /var/log/mcelog.log
        /var/log/logrotate.status
        /var/log/synoupdate.log
"
LogTotalLimitKB=$((300 * 1024))

LogAction() {
        Echo "$(/bin/date -Iseconds) Do   [$*]"
        "$@"
        local ret=$?
        Echo "$(/bin/date -Iseconds) Done [$*], ret [$ret]"
        return $ret
}

CheckSize() { # Mnt
        if [ $# -ne 1 ]; then
                Echo "CheckSize: Wrong usage"
                return 255
        fi

        local Mnt="$1"; shift

        local LogTotalSizeKB=0
        local LogSizeKB=0
        for dir in $BackupDirList; do
                if [ ! -d "$Mnt""$dir" ]; then
                        continue
                fi
                LogSizeKB="$(/bin/du -sx "$Mnt""$dir" | Cut -f 1)"
                LogTotalSizeKB=$((LogTotalSizeKB + LogSizeKB))
        done
        if [ "$LogTotalSizeKB" -gt $LogTotalLimitKB ]; then
                Echo "Log size total $LogTotalSizeKB KB is greater than $LogTotalLimitKB KB. Skip backing up logs."
                return 1
        fi
        return 0
}

CpDirWithMode() { # Src Dest Dir
        if [ $# -ne 3 ]; then
                Echo "CpDirWithMode: Wrong usage"
                return 255
        fi

        local Src="$1"; shift
        local Dest="$1"; shift
        local Dir="$1"; shift

        local Target="$Dir"
        local ParentList
        while [ "." != "$Target" ] && [ "/" != "$Target" ]; do
                ParentList="./$Target $ParentList"
                Target=$(dirname "$Target")
        done
        if [ -n "$ParentList" ]; then
                Tar cf - --no-recursion -C "$Src" $ParentList | Tar xf - -C "$Dest"
        fi
}

CandidateList() { # Src
        if [ $# -ne 1 ]; then
                Echo "CandidateList: Wrong usage"
                return 255
        fi

        local Src="$1"; shift

        local TotalSizeKB=0
        local Candidates

        for file in $CriticalLogs; do
                if [ -f "$Src""$file" ] || [ -d "$Src""$file" ]; then
                        local FileSizeKB
                        FileSizeKB="$(/bin/du -s "$Src""$file" | cut -f 1)"
                        if [ "$((TotalSizeKB + FileSizeKB))" -gt $LogTotalLimitKB ]; then
                                Echo "Adding [$file] size [$FileSizeKB] will exceed limit. Skip." 1>&2
                                continue
                        fi
                        Candidates="$Candidates $file"
                        TotalSizeKB=$((TotalSizeKB + FileSizeKB))
                        Echo "Add [$file] size [$FileSizeKB] to candidate, total [$TotalSizeKB]" 1>&2
                else
                        Echo "[$file] does not exist. skip." 1>&2
                fi
        done
        Echo "$Candidates"
}

CpLogs() { # Src Dest CpCriticalOnly
        if [ $# -ne 3 ]; then
                Echo "CpLogs: Wrong usage"
                return 255
        fi

        local Src="$1"; shift
        local Dest="$1"; shift
        local CpCriticalOnly="$1"; shift

        if [ "yes" = "$CpCriticalOnly" ]; then
                LogAction ListBackupDirContent "$Mnt"
                CandidateLogs="$(CandidateList "$Mnt")"
                if [ -z "$CandidateLogs" ]; then
                        Echo "No critical log files exists to backup"
                        return 0
                fi
        else
                CandidateLogs="$BackupDirList"
        fi

        for file in $CandidateLogs; do
                local dir
                dir="$(/bin/dirname "$file")"
                if [ "." != "$dir" ] && [ "/" != "$dir" ]; then
                        LogAction CpDirWithMode "$Src" "$Dest" "$dir"
                fi
                LogAction Cp -a "$Src""$file" "$Dest""$dir"
        done
}

ListBackupDirContent() { # Mnt
        if [ $# -ne 1 ]; then
                Echo "ListBackupDirContent: Wrong usage"
                return 255
        fi

        local Mnt="$1"; shift
        for dir in $BackupDirList; do
                Echo "===== DIR CONTENT OF root [$dir]:"
                Ls -l -a -R "$Mnt""$dir"
                Echo "===== DIR CONTENT OF root [$dir]: end"
        done
}

BackupLog() { # Mnt LogTmp
        if [ $# -ne 2 ]; then
                Echo "BackupLog: Wrong usage"
                return 255
        fi

        local Mnt="$1"; shift
        local LogTmp="$1"; shift
        local OverLimit

        if ! CheckSize "$Mnt"; then
                Echo "Check size failed."
                OverLimit="yes"
        fi
        if [ ! -d "$LogTmp" ]; then
                if ! LogAction Mkdir -p "$LogTmp"; then
                        Echo "Failed to create [$LogTmp]"
                        return 1
                fi
        fi
        LogAction CpLogs "$Mnt" "$LogTmp" "$OverLimit"
        return 0
}

SetAppendOnlyAttr() { # Mnt
        if [ $# -ne 1 ]; then
                Echo "RestoreLog: Wrong usage"
                return 255
        fi

        local Mnt="$1"; shift

        for file in "$Mnt"/var/log/rm.log* ; do
                if [ ! -f "$file" ]; then
                        continue
                fi
                LogAction /bin/chattr +a "$file"
        done
}

RestoreLog() { # Mnt LogTmp
        if [ $# -ne 2 ]; then
                Echo "RestoreLog: Wrong usage"
                return 255
        fi

        local Mnt="$1"; shift
        local LogTmp="$1"; shift

        if [ ! -d "$LogTmp" ]; then
                Echo "[$LogTmp] does not exist. Ignore restoring."
                return 0
        fi
        LogAction CpLogs "$LogTmp" "$Mnt" no
        LogAction Rm -rf "$LogTmp"
        LogAction SetAppendOnlyAttr "$Mnt"
}

CleanupRootDevice() { # Mnt
        if [ $# -ne 1 ]; then
                Echo "CleanupRootDevice: Wrong usage"
                return 255
        fi

        local Mnt="$1"; shift
        local LogTmp="/tmp/backuplog-XXXXXX"

        Echo "CleanupRootDevice: Start"

        if [ "$IsUCOrXA" = "yes" ]; then
                LogAction BackupLog "$Mnt" "$LogTmp"
        fi

        Umount "$Mnt"
        MakeSystemFS -E discard "$RootDevice"
        Mount "$RootDevice" "$Mnt"
        /bin/touch "$Mnt"/.NormalShutdown

        if [ "$IsUCOrXA" = "yes" ]; then
                LogAction RestoreLog "$Mnt" "$LogTmp"
        fi

        Echo "CleanupRootDevice: Finished"
}

CleanupRootDevice "$@"
