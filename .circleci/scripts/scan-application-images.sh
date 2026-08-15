#!/usr/bin/env bash

set -euo pipefail

source "$(dirname "$0")/lib/application-images.sh"

readonly TRIVY_IMAGE="aquasec/trivy:0.73.0@sha256:4bbf3824d974b70f27631005e2e6194d4d8fbd6e72c4a9e04cf521e25c5cb07f"

configure_candidate_images
ensure_jq
mkdir -p reports/trivy-images reports/sbom .trivy-cache

trivy() {
  docker run --rm \
    -v /var/run/docker.sock:/var/run/docker.sock \
    -v "$PWD/reports:/reports" \
    -v "$PWD/.trivy-cache:/root/.cache/" \
    "$TRIVY_IMAGE" "$@"
}

gate_high_or_critical_findings() {
  local service="$1"
  local report="reports/trivy-images/${service}.json"

  [[ -s "$report" ]] || {
    echo "Trivy did not create an image JSON report for ${service}." >&2
    return 1
  }

  jq empty "$report" >/dev/null 2>&1 || {
    echo "Trivy created an invalid image JSON report for ${service}." >&2
    return 1
  }

  jq -e '
    [
      .Results[]?.Vulnerabilities[]?
      | select(.Severity == "HIGH" or .Severity == "CRITICAL")
    ] | length == 0
  ' "$report" >/dev/null || {
    echo "Trivy reported at least one HIGH or CRITICAL vulnerability for ${service}." >&2
    return 1
  }
}

image_scan_failed=0
mapfile -t image_references < <(candidate_image_references)
for image in "${image_references[@]}"; do
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

  if ! gate_high_or_critical_findings "$service"; then
    image_scan_failed=1
  fi
done

if (( image_scan_failed )); then
  echo "At least one application image has HIGH or CRITICAL vulnerabilities." >&2
  exit 1
fi
