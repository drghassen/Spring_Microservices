#!/usr/bin/env bash

set -euo pipefail

source "$(dirname "$0")/lib/application-images.sh"

readonly ORAS_IMAGE="ghcr.io/oras-project/oras:v1.3.0@sha256:6ce045ce069a89934d6666b8b49f9c4c0145201bd6de6dbe2aee267814c55468"
readonly SBOM_ARTIFACT_TYPE="application/vnd.cyclonedx+json"
readonly SBOM_DIRECTORY="sbom-reports"

: "${ACR_LOGIN_SERVER:?ACR_LOGIN_SERVER must be defined in the acr-publish CircleCI context}"
: "${ACR_USERNAME:?ACR_USERNAME must be defined in the acr-publish CircleCI context}"
: "${ACR_PASSWORD:?ACR_PASSWORD must be defined in the acr-publish CircleCI context}"

configure_candidate_images

for service in "${APP_SERVICES[@]}"; do
  sbom_file="${SBOM_DIRECTORY}/${service}/${service}-${IMAGE_TAG}.cdx.json"
  [[ -s "$sbom_file" ]] || {
    echo "SBOM is missing for ${service}: ${sbom_file}" >&2
    exit 1
  }
done

docker pull "$ORAS_IMAGE"

echo "$ACR_PASSWORD" | docker login "$ACR_LOGIN_SERVER" \
  --username "$ACR_USERNAME" \
  --password-stdin

readonly DOCKER_REGISTRY_CONFIG="${HOME}/.docker/config.json"
[[ -f "$DOCKER_REGISTRY_CONFIG" ]] || {
  echo "Docker registry authentication file is missing: ${DOCKER_REGISTRY_CONFIG}" >&2
  exit 1
}

oras() {
  docker run --rm \
    -v "$DOCKER_REGISTRY_CONFIG:/docker-config.json:ro" \
    -v "$PWD/$SBOM_DIRECTORY:/sbom:ro" \
    -w /sbom \
    "$ORAS_IMAGE" "$@"
}

mkdir -p reports
: > reports/acr-image-manifest.txt
for service in "${APP_SERVICES[@]}"; do
  source_image="${IMAGE_REPOSITORY_PREFIX}/${service}:${IMAGE_TAG}"
  target_image="${ACR_LOGIN_SERVER}/${service}:${IMAGE_TAG}"

  docker image tag "$source_image" "$target_image"
  docker push "$target_image"

  target_digest="$(oras resolve \
    --registry-config /docker-config.json \
    "$target_image")"
  [[ "$target_digest" =~ ^sha256:[0-9a-f]{64}$ ]] || {
    echo "ORAS returned an invalid digest for ${target_image}: ${target_digest}" >&2
    exit 1
  }

  target_reference="${ACR_LOGIN_SERVER}/${service}@${target_digest}"
  oras attach \
    --registry-config /docker-config.json \
    --no-tty \
    --artifact-type "$SBOM_ARTIFACT_TYPE" \
    "$target_reference" \
    "${service}/${service}-${IMAGE_TAG}.cdx.json:${SBOM_ARTIFACT_TYPE}"

  printf '%s\n' "$target_reference" >> reports/acr-image-manifest.txt
done
