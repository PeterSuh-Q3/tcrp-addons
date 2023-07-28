#!/bin/sh

if [ "${1}" = "modules" ]; then
    echo "Starting ttyd, listening on port: 7681"
    cp lrz /usr/sbin/rz
    cp lsz /usr/sbin/sz
    chmod +x ttyd
    ./ttyd login > /dev/null 2>&1 &
fi
