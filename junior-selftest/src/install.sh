#!/bin/sh
# Copyright (C) 2026 PeterSuh-Q3. See repository LICENSE.
# Started by the Redpill on_patches hook inside DSM junior.
[ "$1" = patches ] || exit 0
[ -x /linuxrc.syno ] || exit 0
[ -e /tmp/junior-selftest.pid ] && kill -0 "$(cat /tmp/junior-selftest.pid)" 2>/dev/null && exit 0
cp ./selftest.sh /tmp/junior-selftest.sh || exit 1
cp ./fb-status /tmp/junior-fb-status || exit 1
chmod 755 /tmp/junior-selftest.sh /tmp/junior-fb-status
(trap '' HUP; exec /bin/sh /tmp/junior-selftest.sh </dev/null >>/tmp/junior-selftest.log 2>&1) &
echo "$!" >/tmp/junior-selftest.pid
exit 0
