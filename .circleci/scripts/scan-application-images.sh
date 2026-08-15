#!/usr/bin/env bash

set -euo pipefail

source "$(dirname "$0")/lib/application-images.sh"

readonly TRIVY_IMAGE="aquasec/trivy:0.73.0"

configure_candidate_images
mkdir -p reports/trivy-images reports/sbom .trivy-cache

trivy() {
  docker run --rm \
    -v /var/run/docker.sock:/var/run/docker.sock \
    -v "$PWD/reports:/reports" \
    -v "$PWD/.trivy-cache:/root/.cache/" \
    "$TRIVY_IMAGE" "$@"
}

image_scan_failed=0
for image in $(candidate_image_references); do
  service="${image#*/}"
  service="${service%%:*}"

  trivy image \
    --format cyclonedx \
    --output "/reports/sbom/${service}.cdx.json" \
    --no-progress \
    --skip-version-check \
    --timeout 20m \
    "$image"

  trivy image \
    --scanners vuln \
    --severity HIGH,CRITICAL \
    --exit-code 0 \
    --format json \
    --output "/reports/trivy-images/${service}.json" \
    --no-progress \
    --skip-version-check \
    --timeout 20m \
    "$image"

  if ! trivy image \
    --scanners vuln \
    --severity HIGH,CRITICAL \
    --exit-code 1 \
    --no-progress \
    --skip-version-check \
    --timeout 20m \
    "$image"; then
    image_scan_failed=1
  fi
done

if (( image_scan_failed )); then
  echo "At least one application image has HIGH or CRITICAL vulnerabilities." >&2
  exit 1
fi
