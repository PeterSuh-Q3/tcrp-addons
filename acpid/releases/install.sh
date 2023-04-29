#!/usr/bin/env ash

### USUALLY SCEMD is the last process run in init, so when scemd is running we are most
# probably certain that system has finish init process

if [ `mount | grep tmpRoot | wc -l` -gt 0 ] ; then
  HASBOOTED="yes"
  echo "System passed junior"
else
  echo "System is booting"
  HASBOOTED="no"
fi

if [ "$HASBOOTED" = "no" ]; then
  echo "acpid - early"
  echo "extract cgetty.tgz to /usr/sbin/ "
  tar xfz /exts/acpid/acpid.tgz -C /

  #/usr/sbin/acpid
elif [ "$HASBOOTED" = "yes" ]; then
  echo "acpid - late"
  #/usr/bin/killall acpid
  echo "Installing daemon for ACPI button"
  cp -v /usr/sbin/acpid /tmpRoot/usr/sbin/acpid
  mkdir -p /tmpRoot/etc/acpi/events/
  cp -v /etc/acpi/events/power /tmpRoot/etc/acpi/events/power
  cp -v /etc/acpi/power.sh /tmpRoot/etc/acpi/power.sh
  cp -v /usr/lib/systemd/system/acpid.service /tmpRoot/usr/lib/systemd/system/acpid.service
  mkdir -vp /tmpRoot/lib/systemd/system/multi-user.target.wants
  ln -vsf /usr/lib/systemd/system/acpid.service /tmpRoot/lib/systemd/system/multi-user.target.wants/acpid.service
fi
