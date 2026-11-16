#!/bin/sh
if [ "$1" = rcExit ] && [ -s /addons/mshell-wifi.conf ]; then
    sh /exts/wifi-tools/wifi-connect.sh </dev/null >/dev/null 2>&1 &
fi
