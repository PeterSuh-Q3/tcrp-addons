#!/usr/bin/env ash

### USUALLY SCEMD is the last process run in init, so when scemd is running we are most
# probably certain that system has finish init process

if [ "${1}" = "early" ]; then
  echo "Installing addon abusyboxupgrade - ${1}"
  echo "extract usr-busybox.tgz to /usr/bin/ "
  tar vxfz usr-busybox.tgz -C /usr/bin/
  echo "make syboliclink for new busybox "
  /usr/bin/busybox --install -s /usr/bin
  cat << 'EOF' > /usr/bin/get_key_value
#!/bin/sh
grep "^${2}=" "${1}" | head -n1 | cut -d'=' -f2-
EOF
  chmod +x /usr/bin/get_key_value
fi
