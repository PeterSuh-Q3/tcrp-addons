#!/bin/bash

#
# Copyright (C) 2023-2026 PeterSuh-Q3
# https://github.com/PeterSuh-Q3
#
# This installer script is licensed under the
# PeterSuh-Q3 Non-Commercial Source-Available License.
#
# The kernel module installed by this script is a separate component
# distributed under its applicable GPL-compatible license.
#
modify_synoinfo() {
# add supportraidgroup="no" , support_syno_hybrid_raid="yes" to /etc/synoinfo.conf for avtive SHR 2023.07.10
  if [ -f /tmpRoot/etc/synoinfo.conf ]; then
    echo 'add supportraidgroup="no" to /tmpRoot/etc/synoinfo.conf'
    if grep -q 'supportraidgroup' /tmpRoot/etc/synoinfo.conf; then
      sed -i 's#supportraidgroup=.*#supportraidgroup="no"#' /tmpRoot/etc/synoinfo.conf
    else
      echo 'supportraidgroup="no"' >> /tmpRoot/etc/synoinfo.conf
    fi
    cat /tmpRoot/etc/synoinfo.conf | grep supportraidgroup

    echo 'add support_syno_hybrid_raid="yes" to /tmpRoot/etc/synoinfo.conf'
    if grep -q 'support_syno_hybrid_raid' /tmpRoot/etc/synoinfo.conf; then
      sed -i 's#support_syno_hybrid_raid=.*#support_syno_hybrid_raid="yes"#' /tmpRoot/etc/synoinfo.conf
    else
      echo 'support_syno_hybrid_raid="yes"' >> /tmpRoot/etc/synoinfo.conf
    fi
    cat /tmpRoot/etc/synoinfo.conf | grep support_syno_hybrid_raid
  fi

  if [ -f /tmpRoot/etc.defaults/synoinfo.conf ]; then
    echo 'add supportraidgroup="no" to /tmpRoot/etc.defaults/synoinfo.conf'
    if grep -q 'supportraidgroup' /tmpRoot/etc.defaults/synoinfo.conf; then
      sed -i 's#supportraidgroup=.*#supportraidgroup="no"#' /tmpRoot/etc.defaults/synoinfo.conf
    else
      echo 'supportraidgroup="no"' >> /tmpRoot/etc.defaults/synoinfo.conf
    fi
    cat /tmpRoot/etc.defaults/synoinfo.conf | grep supportraidgroup

    echo 'add support_syno_hybrid_raid="yes" to /tmpRoot/etc.defaults/synoinfo.conf'
    if grep -q 'support_syno_hybrid_raid' /tmpRoot/etc.defaults/synoinfo.conf; then
      sed -i 's#support_syno_hybrid_raid=.*#support_syno_hybrid_raid="yes"#' /tmpRoot/etc.defaults/synoinfo.conf
    else
      echo 'support_syno_hybrid_raid="yes"' >> /tmpRoot/etc.defaults/synoinfo.conf
    fi
    cat /tmpRoot/etc.defaults/synoinfo.conf | grep support_syno_hybrid_raid
  fi

}

if [ "${1}" = "late" ]; then
  echo "shr - late"
  echo "Installing shr enabler tools"
  modify_synoinfo
fi
