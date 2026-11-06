#!/bin/sh
# Bounded DSM data-volume recovery reboot retries. No RAID/LVM repair.
set -u
LOG=/var/log/mshell-volume-recovery.log
STATE=/var/lib/mshell-volume-recovery
RETRY_STATE=$STATE/reboot-retry-state
MAX_REBOOT_ATTEMPTS=2
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
build=$(awk -F= '$1=="buildnumber" {gsub(/["[:space:]]/,"",$2); print $2; exit}' "$dsm_version_file")
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
    failed_volume=
    while IFS="$(printf '\t')" read -r mnt _dev _fsuuid _lvuuid; do
        [ -n "$mnt" ] || continue
        if ! awk -v m="$mnt" '$2==m {found=1} END {exit !found}' /proc/mounts; then
            failed=1
            [ -n "$failed_volume" ] || failed_volume=$mnt
            continue
        fi
        if ! "$SYNOSTGVOLUME" --is-writable "$mnt" >/dev/null 2>&1; then
            failed=1
            [ -n "$failed_volume" ] || failed_volume=$mnt
        fi
    done <<EOF_VOLUMES
$volumes
EOF_VOLUMES
    [ "$failed" -eq 0 ]
}
while [ "$tries" -lt 18 ]; do
    if volume_ready; then
        if [ -e "$RETRY_STATE" ]; then
            rm -f "$RETRY_STATE"
            log 'RETRY_STATE=cleared volume_healthy'
        fi
        exit 0
    fi
    sleep 10
    tries=$((tries+1))
done

# Record live storage state for diagnosis. Do not reboot on metadata disagreement.
mkdir -p "$STATE" || noop 'cannot create persistent state directory'
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

# Scope retries to this DSM/storage identity. A newly observed post-upgrade
# event also starts a fresh retry series; healthy volumes clear the state above.
model=$(awk -F= '$1=="unique" {gsub(/["[:space:]]/,"",$2); print $2; exit}' /etc.defaults/synoinfo.conf 2>/dev/null)
storage_identity=$(jq -c 'sort_by(.id) | map({id,uuid,raids:(.raids|map({md_path,uuid})|sort_by(.md_path)),volumes:(.volumes|map({mnt_path,fs_uuid,uuid})|sort_by(.mnt_path))})' "$SPACE_TABLE" 2>/dev/null) || noop 'cannot derive storage retry identity'
identity=$(printf 'DSM=%s.%s.%s\nMODULE=%s\nMODEL=%s\nSTORAGE=%s\n' "$major" "$minor" "$build" "$module_type" "$model" "$storage_identity" | sha256sum | awk '{print $1}')
[ -n "$identity" ] || noop 'cannot hash storage retry identity'
boot_id=$(cat /proc/sys/kernel/random/boot_id 2>/dev/null) || noop 'boot ID unavailable'
[ -n "$boot_id" ] || noop 'boot ID unavailable'
upgrade_line=$(grep -F 'IS_FIRST_LOGIN_AFTER_UPGRADE=1' /var/log/synobootup.log 2>/dev/null | tail -n 1 || true)
upgrade_event=
if [ -n "$upgrade_line" ]; then
    upgrade_event=$(printf '%s' "$upgrade_line" | sha256sum | awk '{print $1}')
fi

attempts=0
last_boot=
old_identity=
old_upgrade_event=
if [ -r "$RETRY_STATE" ]; then
    attempts=$(sed -n 's/^attempts=//p' "$RETRY_STATE" | head -n 1)
    last_boot=$(sed -n 's/^last_boot=//p' "$RETRY_STATE" | head -n 1)
    old_identity=$(sed -n 's/^identity=//p' "$RETRY_STATE" | head -n 1)
    old_upgrade_event=$(sed -n 's/^upgrade_event=//p' "$RETRY_STATE" | head -n 1)
    case "$attempts" in ''|*[!0-9]*) noop 'retry state is malformed' ;; esac
fi

if [ -n "$old_identity" ] && [ "$old_identity" != "$identity" ]; then
    log 'RETRY_STATE=reset identity_changed'
    attempts=0
    old_upgrade_event=
fi
if [ -n "$upgrade_event" ] && [ "$upgrade_event" != "$old_upgrade_event" ]; then
    log 'RETRY_STATE=reset new_post_upgrade_event'
    attempts=0
    old_upgrade_event=$upgrade_event
fi
[ "$last_boot" != "$boot_id" ] || noop 'reboot already requested during this boot'
[ "$attempts" -lt "$MAX_REBOOT_ATTEMPTS" ] || noop "retry budget exhausted attempts=$attempts; waiting for healthy volume or new migration identity"

# Persist a bounded retry ledger before invoking reboot. Unlike the old global
# marker, it auto-clears on a healthy boot and resets for changed migration or
# storage identity. Keep at most two reboot requests per incident.
next_attempt=$((attempts+1))
if [ -z "$upgrade_event" ]; then upgrade_event=$old_upgrade_event; fi
tmp="$RETRY_STATE.tmp.$$"
(umask 077; printf 'attempts=%s\nlast_boot=%s\nidentity=%s\nupgrade_event=%s\n' \
    "$next_attempt" "$boot_id" "$identity" "$upgrade_event" >"$tmp") || { rm -f "$tmp"; noop 'cannot write retry state'; }
if ! mv "$tmp" "$RETRY_STATE" || [ ! -s "$RETRY_STATE" ]; then rm -f "$tmp"; noop 'cannot persist retry state'; fi
chmod 600 "$RETRY_STATE" || noop 'cannot secure retry state'
sync
log "DECISION=reboot attempt=$next_attempt/$MAX_REBOOT_ATTEMPTS retry_state=persisted"
NOTIFY=/usr/syno/bin/synodsmnotify
failed_volume=${failed_volume:-/volume1}
volume_id=${failed_volume##*/}
case "$volume_id" in
    volume[0-9]*) notify_volume="볼륨 ${volume_id#volume}" ;;
    *) notify_volume='볼륨' ;;
esac
notify_operation='볼륨 복구'
notify_args=$(jq -cn --arg volume "$notify_volume" --arg operation "$notify_operation" \
    '{"%VOLUME_NAME%":$volume,"%VOLUME_OFFLINE_OP%":$operation}') || notify_args=
if [ -x "$NOTIFY" ] && [ -n "$notify_args" ] && \
    "$NOTIFY" -e false -b false '@administrators' 'StrMgrVolumeOfflineOpPanic' "$notify_args"; then
    log 'DSM_NOTIFICATION=sent recipient=@administrators'
else
    log 'DSM_NOTIFICATION=failed; continuing with bounded reboot attempt'
fi
/sbin/reboot
exit $?
