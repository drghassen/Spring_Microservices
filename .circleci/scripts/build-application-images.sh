#!/usr/bin/env bash

set -euo pipefail

source "$(dirname "$0")/lib/application-images.sh"

configure_candidate_images

docker compose config -q
docker compose build "${APP_SERVICES[@]}"

mapfile -t image_references < <(candidate_image_references)
docker image inspect "${image_references[@]}" >/dev/null

mkdir -p reports
printf '%s\n' "${image_references[@]}" > reports/candidate-image-manifest.txt
