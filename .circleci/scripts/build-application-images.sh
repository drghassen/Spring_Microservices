#!/usr/bin/env bash

set -euo pipefail

source "$(dirname "$0")/lib/application-images.sh"

configure_candidate_images
: "${CIRCLE_BUILD_NUM:?CIRCLE_BUILD_NUM must be defined by CircleCI}"
export COMPOSE_PROJECT_NAME="ci${CIRCLE_BUILD_NUM}"

create_ci_compose_env_file
trap cleanup_ci_compose_env_file EXIT

selected_services=("$@")
if (( ${#selected_services[@]} == 0 )); then
  selected_services=("${APP_SERVICES[@]}")
fi

ci_compose config -q
ci_compose build "${selected_services[@]}"

mapfile -t image_references < <(candidate_image_references "${selected_services[@]}")
docker image inspect "${image_references[@]}" >/dev/null

mkdir -p reports
printf '%s\n' "${image_references[@]}" > reports/candidate-image-manifest-"${selected_services[0]}".txt
