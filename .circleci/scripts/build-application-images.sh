#!/usr/bin/env bash

set -euo pipefail

source "$(dirname "$0")/lib/application-images.sh"

configure_candidate_images

mkdir -p ci-images
docker compose config -q
docker compose build "${APP_SERVICES[@]}"

mapfile -t image_references < <(candidate_image_references)
docker image inspect "${image_references[@]}" >/dev/null
docker image save "${image_references[@]}" | gzip -1 > "$IMAGE_ARCHIVE"

printf '%s\n' "${image_references[@]}" > ci-images/manifest.txt
