#!/bin/sh
set -eu

here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
CC=${CC:-x86_64-linux-gnu-gcc}
DRM_INCLUDE=${DRM_INCLUDE:-/usr/include/libdrm}

"$CC" -D__user= -static -Os -s -Wall -Wextra -Werror \
    -I"$DRM_INCLUDE" -I"$here/third_party" -o "$here/kms-display" \
    "$here/kms-display.c" "$here/third_party/qrcodegen.c"
