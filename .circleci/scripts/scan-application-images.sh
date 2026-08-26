#!/usr/bin/env bash

set -euo pipefail

source "$(dirname "$0")/lib/application-images.sh"

readonly TRIVY_IMAGE="aquasec/trivy:0.73.0@sha256:4bbf3824d974b70f27631005e2e6194d4d8fbd6e72c4a9e04cf521e25c5cb07f"
readonly JAVA_SERVICES=(
  config-server discovery-service gateway games-service library-service
  order-service payment-service user-service
)

configure_candidate_images
ensure_jq
mkdir -p reports/trivy-images

TRIVY_CACHE_VOLUME="trivy-cache-$(date +%s)-${RANDOM}-${RANDOM}"
docker volume create "$TRIVY_CACHE_VOLUME" >/dev/null

cleanup_trivy_cache() {
  local status=$?

  docker volume rm -f "$TRIVY_CACHE_VOLUME" >/dev/null 2>&1 || true
  return "$status"
}

trap cleanup_trivy_cache EXIT

trivy() {
  docker run --rm \
    -v /var/run/docker.sock:/var/run/docker.sock \
    -v "$PWD/reports:/reports" \
    -v "$TRIVY_CACHE_VOLUME:/root/.cache/trivy:rw" \
    "$TRIVY_IMAGE" "$@"
}

write_scan_error_report() {
  local service="$1"
  local report="reports/trivy-images/${service}.json"

  jq -n --arg service "$service" '
    {
      SchemaVersion: 2,
      ArtifactName: ("ci.local/" + $service),
      ArtifactType: "container_image",
      Results: [],
      ScanError: "Trivy scan failed; inspect CI job logs."
    }
  ' > "$report"
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
    return 2
  }

  jq -e '.ScanError? == null' "$report" >/dev/null || {
    echo "Trivy scan failed for ${service}; inspect CI job logs." >&2
    return 2
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

mapfile -t image_references < <(candidate_image_references "${JAVA_SERVICES[@]}")

if ! trivy image \
  --download-db-only \
  --timeout 30m \
  --no-progress \
  --skip-version-check; then
  for image in "${image_references[@]}"; do
    service="${image#*/}"
    service="${service%%:*}"
    write_scan_error_report "$service"
  done
  echo "Trivy vulnerability database preload failed; vulnerability scanning was not performed." >&2
  exit 2
fi

if ! trivy image \
  --download-java-db-only \
  --timeout 30m \
  --no-progress \
  --skip-version-check; then
  for image in "${image_references[@]}"; do
    service="${image#*/}"
    service="${service%%:*}"
    write_scan_error_report "$service"
  done
  echo "Trivy Java database preload failed; vulnerability scanning was not performed." >&2
  exit 2
fi

image_scan_error=0
image_vulnerabilities_found=0
for image in "${image_references[@]}"; do
  service="${image#*/}"
  service="${service%%:*}"
  report="reports/trivy-images/${service}.json"

  rm -f -- "$report"

  if ! trivy image \
    --scanners vuln \
    --severity HIGH,CRITICAL \
    --exit-code 0 \
    --format json \
    --output "/reports/trivy-images/${service}.json" \
    --no-progress \
    --skip-version-check \
    --timeout 15m \
    --skip-db-update \
    --skip-java-db-update \
    "$image"; then
    write_scan_error_report "$service"
    image_scan_error=1
    continue
  fi

  if gate_high_or_critical_findings "$service"; then
    continue
  else
    gate_status=$?
    if (( gate_status == 2 )); then
      image_scan_error=1
    else
      image_vulnerabilities_found=1
    fi
  fi
done

if (( image_scan_error )); then
  echo "At least one application image could not be scanned; inspect its JSON error report and CI job logs." >&2
  exit 2
fi

if (( image_vulnerabilities_found )); then
  echo "At least one application image has HIGH or CRITICAL vulnerabilities." >&2
  exit 1
fi
