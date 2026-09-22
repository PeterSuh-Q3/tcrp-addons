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
if [ "${1}" = "late" ]; then
  echo "Copying lsiutil to HD"
  cp -vf lsiutil /tmpRoot/usr/sbin/lsiutil
fi
