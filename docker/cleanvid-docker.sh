#!/usr/bin/env bash

export CLEANVID_IMAGE="${CLEANVID_DOCKER_IMAGE:-ghcr.io/mmguero/cleanvid:latest}"

# run from directory containing video/srt files

docker run --rm -t \
  -u $(id -u):$(id -g) \
  -v "$(realpath "${PWD}"):${PWD}" \
  -w "${PWD}" \
  "$CLEANVID_IMAGE" "$@"
