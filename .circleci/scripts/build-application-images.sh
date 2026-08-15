#!/usr/bin/env bash

set -euo pipefail

source "$(dirname "$0")/lib/application-images.sh"

configure_candidate_images
configure_runtime_environment

selected_services=("$@")
if (( ${#selected_services[@]} == 0 )); then
  selected_services=("${APP_SERVICES[@]}")
fi

docker compose config -q
docker compose build "${selected_services[@]}"

mapfile -t image_references < <(candidate_image_references "${selected_services[@]}")
docker image inspect "${image_references[@]}" >/dev/null

mkdir -p reports
printf '%s\n' "${image_references[@]}" > reports/candidate-image-manifest-"${selected_services[0]}".txt
