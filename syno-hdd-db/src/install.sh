#!/usr/bin/env bash

if [ "${1}" = "late" ]; then
    /tmpRoot/bin/hdparm -I /dev/sd*
fi

