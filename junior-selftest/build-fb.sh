#!/bin/sh
set -eu
cd "$(dirname "$0")"
docker run --rm --platform linux/amd64 -v "$PWD/src:/src" -w /src alpine:3.20 \
    sh -c 'apk add --no-cache gcc musl-dev linux-headers >/dev/null && gcc -Os -static -Wall -Wextra -Werror -o fb-status fb-status.c'
shasum -a 256 src/fb-status
