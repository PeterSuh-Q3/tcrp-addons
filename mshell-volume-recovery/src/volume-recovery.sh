#!/bin/sh
# One-shot DSM data-volume recovery reboot. Read-only diagnosis; no RAID/LVM repair.
set -u
LOG=/var/log/mshell-volume-recovery.log
STATE=/var/lib/mshell-volume-recovery
MARKER=$STATE/reboot-attempted
SPACE_TABLE=/var/lib/space/space_table
SYNOSTGVOLUME=/usr/syno/sbin/synostgvolume
log() { printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >>"$LOG"; }
noop() { log "NOOP: $*"; exit 0; }

# Gate only the two supported PML paths.
[ -r /usr/mshell/MODULE_TYPE ] || noop 'missing MODULE_TYPE'
module_type=$(tr -d '\r\n' </usr/mshell/MODULE_TYPE)
case "$module_type" in 'all-modules (PML)'|'custom-modules (PML)') ;; *) noop "module type=$module_type" ;; esac

# /usr/mshell/VERSION is the MSHELL version. DSM's version comes from VERSION.
dsm_version_file=/etc.defaults/VERSION
[ -r "$dsm_version_file" ] || dsm_version_file=/etc/VERSION
[ -r "$dsm_version_file" ] || noop 'DSM VERSION file unavailable'
major=$(awk -F= '$1=="majorversion" {gsub(/["[:space:]]/,"",$2); print $2; exit}' "$dsm_version_file")
minor=$(awk -F= '$1=="minorversion" {gsub(/["[:space:]]/,"",$2); print $2; exit}' "$dsm_version_file")
[ -n "$major" ] && [ -n "$minor" ] || noop 'DSM version is not parseable'
if [ "$major" -lt 7 ] || { [ "$major" -eq 7 ] && [ "$minor" -lt 3 ]; }; then noop "DSM version=$major.$minor below 7.3"; fi

# If any processor lacks BMI2, take the compatibility path.
if ! awk '/^flags[[:space:]]*:/ {seen=1; if ($0 !~ /(^|[[:space:]])bmi2([[:space:]]|$)/) missing=1} END {exit !(seen && missing)}' /proc/cpuinfo; then
    noop 'CPU BMI2 is present on all reported processors'
fi

[ -r "$SPACE_TABLE" ] || noop 'space_table unavailable'
command -v jq >/dev/null 2>&1 || noop 'jq unavailable'
volumes=$(jq -er '[.[] | .volumes[]? | select(.mnt_path != null and .dev_path != null) | [.mnt_path,.dev_path,(.fs_uuid // ""),(.uuid // "")]] | .[] | @tsv' "$SPACE_TABLE" 2>/dev/null) || noop 'no parseable registered volumes'
[ -n "$volumes" ] || noop 'no registered data volumes'

# Wait up to 3 minutes for ordinary DSM startup and delayed volume assembly.
tries=0
volume_ready() {
    failed=0
    while IFS="$(printf '\t')" read -r mnt dev fsuuid lvuuid; do
        [ -n "$mnt" ] || continue
        awk -v m="$mnt" '$2==m {found=1} END {exit !found}' /proc/mounts || { failed=1; continue; }
        "$SYNOSTGVOLUME" --is-writable "$mnt" >/dev/null 2>&1 || failed=1
    done <<EOF_VOLUMES
$volumes
EOF_VOLUMES
    [ "$failed" -eq 0 ]
}
while [ "$tries" -lt 18 ]; do
    volume_ready && exit 0
    sleep 10
    tries=$((tries+1))
done

# Record live storage state for diagnosis. Do not reboot on metadata disagreement.
mkdir -p "$STATE" || noop 'cannot create persistent state directory'
[ -e "$MARKER" ] && noop 'one-shot reboot marker already exists'
log "PERSISTENT_VOLUME_FAILURE module_type=$module_type DSM=$major.$minor BMI2=absent"
log "SPACE_TABLE=$(cat "$SPACE_TABLE" 2>/dev/null)"
log "MDSTAT=$(cat /proc/mdstat 2>/dev/null | tr '\n' ';')"
log "MOUNTS=$(awk '$2 ~ /^\/volume[0-9]+$/ {print $1 ":" $2}' /proc/mounts | tr '\n' ';')"

# Require an assemble-eligible, present pool with no reported failed members.
# Any ambiguous/missing/faulty state fails closed and leaves the host running.
reboot_eligible=$(jq -er 'all(.[]; .can_reboot_assemble == true and .missing == false and ((.faulty_disks // [])|length)==0 and ((.dropped_disks // [])|length)==0)' "$SPACE_TABLE" 2>/dev/null) || noop 'storage state malformed'
[ "$reboot_eligible" = true ] || noop 'storage metadata is not safely assemble-eligible'

# Check the expected array and volume group still exist. A disagreement is
# treated as possible storage damage and is never an automatic reboot trigger.
while IFS= read -r md; do
    [ -n "$md" ] || continue
    md_name=${md##*/}
    grep -Eq "^[[:space:]]*${md_name}[[:space:]]*: active" /proc/mdstat || noop "expected array $md is not active"
done <<EOF_MD
$(jq -r '.[].raids[]?.md_path // empty' "$SPACE_TABLE" 2>/dev/null)
EOF_MD
while IFS= read -r vg; do
    [ -n "$vg" ] || continue
    [ -d "$vg" ] || noop "expected volume group path $vg is absent"
done <<EOF_VG
$(jq -r '.[].vg_info.vg_path // empty' "$SPACE_TABLE" 2>/dev/null)
EOF_VG

# Fail-closed one-shot: atomically persist and verify before issuing reboot.
tmp="$MARKER.tmp.$$"
(umask 077; printf 'attempted=%s\nDSM=%s.%s\nmodule_type=%s\n' "$(date '+%s')" "$major" "$minor" "$module_type" >"$tmp") || { rm -f "$tmp"; noop 'cannot write reboot marker'; }
if ! mv "$tmp" "$MARKER" || [ ! -s "$MARKER" ]; then rm -f "$tmp"; noop 'cannot persist reboot marker'; fi
sync
log 'DECISION=reboot_once marker=persisted'
NOTIFY=/usr/syno/bin/synodsmnotify
notify_title='Volume recovery reboot'
notify_message="A persistent data-volume mount failure was detected on this DSM $major.$minor system. DSM will reboot once to retry volume assembly. If the volume remains unavailable afterward, automatic reboot will not repeat; manual recovery is required."
if [ -x "$NOTIFY" ] && "$NOTIFY" -l warn '@administrators' "$notify_title" "$notify_message"; then
    log 'DSM_NOTIFICATION=sent recipient=@administrators'
else
    log 'DSM_NOTIFICATION=failed; continuing with one-shot reboot'
fi
/sbin/reboot
exit $?
