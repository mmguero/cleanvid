#!/usr/bin/env bash

IMAGE="${CLEANVID_IMAGE:-ghcr.io/mmguero/cleanvid:latest}"
ENGINE="${CONTAINER_ENGINE:-docker}"

# run from directory containing video/srt files

"${ENGINE}" run --rm -t \
  -u $([[ "$ENGINE" == "podman" ]] && echo 0 || id -u):$([[ "$ENGINE" == "podman" ]] && echo 0 || id -g) \
  -v "$(realpath "${PWD}"):${PWD}" \
  -w "${PWD}" \
  "${IMAGE}" "$@"
