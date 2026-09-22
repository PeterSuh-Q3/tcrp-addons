#!/usr/bin/env ash

#
# Copyright (C) 2026-2026 PeterSuh-Q3
# https://github.com/PeterSuh-Q3
#
# This installer script is licensed under the
# PeterSuh-Q3 Non-Commercial Source-Available License.
#
# The kernel module installed by this script is a separate component
# distributed under its applicable GPL-compatible license.
#
### USUALLY SCEMD is the last process run in init, so when scemd is running we are most
# probably certain that system has finish init process
set -e

if [ "${1}" = "early" ]; then
  echo "Installing addon acovermissingbin - ${1}"
  echo "extract usr.tgz (extra binary) to /usr/sbin/ /usr/lib "
  gunzip -c usr6.tgz | tar xvf - -C /  >/dev/null 2>&1
  cp -vf /usr/sbin/6.2.4/* /usr/sbin/  >/dev/null 2>&1
  cp -vf /usr/lib/6.2.4/* /usr/lib/  >/dev/null 2>&1
fi
