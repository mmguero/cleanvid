#!/usr/bin/env bash

set -e
set -o pipefail
set -u

ENCODING="utf-8"

[[ "$(uname -s)" = 'Darwin' ]] && REALPATH=grealpath || REALPATH=realpath
[[ "$(uname -s)" = 'Darwin' ]] && DIRNAME=gdirname || DIRNAME=dirname
if ! (type "$REALPATH" && type "$DIRNAME" && type docker) > /dev/null; then
  echo "$(basename "${BASH_SOURCE[0]}") requires docker, $REALPATH and $DIRNAME"
  exit 1
fi
export SCRIPT_PATH="$($DIRNAME $($REALPATH -e "${BASH_SOURCE[0]}"))"

pushd "$SCRIPT_PATH"/.. >/dev/null 2>&1
docker build -f docker/Dockerfile -t ghcr.io/mmguero/cleanvid:latest .
popd >/dev/null 2>&1