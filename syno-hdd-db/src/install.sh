#!/usr/bin/env bash

if [ "${1}" = "late" ]; then
    /tmpRoot/usr/syno/bin/syno_hdd_util --ssd_detect
fi

