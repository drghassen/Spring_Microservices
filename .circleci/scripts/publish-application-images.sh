#!/usr/bin/env bash

set -euo pipefail

source "$(dirname "$0")/lib/application-images.sh"

: "${ACR_LOGIN_SERVER:?ACR_LOGIN_SERVER must be defined in the acr-publish CircleCI context}"
: "${ACR_USERNAME:?ACR_USERNAME must be defined in the acr-publish CircleCI context}"
: "${ACR_PASSWORD:?ACR_PASSWORD must be defined in the acr-publish CircleCI context}"

configure_candidate_images

echo "$ACR_PASSWORD" | docker login "$ACR_LOGIN_SERVER" \
  --username "$ACR_USERNAME" \
  --password-stdin

mkdir -p reports
: > reports/acr-image-manifest.txt
for service in "${APP_SERVICES[@]}"; do
  source_image="${IMAGE_REPOSITORY_PREFIX}/${service}:${IMAGE_TAG}"
  target_image="${ACR_LOGIN_SERVER}/${service}:${IMAGE_TAG}"

  docker image tag "$source_image" "$target_image"
  docker push "$target_image"
  printf '%s\n' "$target_image" >> reports/acr-image-manifest.txt
done
