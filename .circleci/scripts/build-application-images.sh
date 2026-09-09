#!/usr/bin/env bash

set -euo pipefail

source "$(dirname "$0")/lib/application-images.sh"
# shellcheck source=lib/report-evidence.sh
source "$(dirname "$0")/lib/report-evidence.sh"

configure_candidate_images
: "${CIRCLE_BUILD_NUM:?CIRCLE_BUILD_NUM must be defined by CircleCI}"
export COMPOSE_PROJECT_NAME="ci${CIRCLE_BUILD_NUM}"

create_ci_compose_env_file
trap cleanup_ci_compose_env_file EXIT

selected_services=("$@")
if (( ${#selected_services[@]} == 0 )); then
  selected_services=("${APP_SERVICES[@]}")
fi

report_header "DEVSECOPS PIPELINE - CONTAINER IMAGE BUILD"
report_pipeline_context
report_field "Builder" "Docker Compose"
report_field "Candidate tag" "$IMAGE_TAG"
report_field "Images requested" "${#selected_services[@]}"
printf '[BUILD] Images: %s\n' "${selected_services[*]}"
report_footer

report_section "Building immutable candidate images"
ci_compose config -q
ci_compose build "${selected_services[@]}"

mapfile -t image_references < <(candidate_image_references "${selected_services[@]}")
docker image inspect "${image_references[@]}" >/dev/null

mkdir -p reports
printf '%s\n' "${image_references[@]}" > reports/candidate-image-manifest-"${selected_services[0]}".txt

report_header "CONTAINER IMAGE BUILD SUMMARY"
for service in "${selected_services[@]}"; do
  printf '[PASS] %-25s %s\n' "$service" "${IMAGE_REPOSITORY_PREFIX}/${service}:${IMAGE_TAG}"
done
report_field "Images built" "${#selected_services[@]}"
report_field "Failures" "0"
report_field "Tag strategy" "Immutable CircleCI pipeline tag"
report_field "RESULT" "ALL REQUESTED CONTAINER IMAGES BUILT"
report_footer
