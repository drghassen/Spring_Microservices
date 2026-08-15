#!/usr/bin/env bash

set -euo pipefail

readonly TRIVY_IMAGE="aquasec/trivy:0.73.0@sha256:4bbf3824d974b70f27631005e2e6194d4d8fbd6e72c4a9e04cf521e25c5cb07f"

mkdir -p reports .trivy-cache

trivy() {
  docker run --rm \
    -v "$PWD:/workspace" \
    -w /workspace \
    -v "$PWD/.trivy-cache:/root/.cache/" \
    "$TRIVY_IMAGE" "$@"
}

trivy fs \
  --scanners secret,misconfig \
  --misconfig-scanners dockerfile \
  --severity HIGH,CRITICAL \
  --exit-code 0 \
  --format json \
  --output reports/trivy-filesystem.json \
  --offline-scan \
  --skip-dirs reports \
  --no-progress \
  --skip-version-check \
  --timeout 20m \
  .

trivy fs \
  --scanners secret,misconfig \
  --misconfig-scanners dockerfile \
  --severity HIGH,CRITICAL \
  --exit-code 1 \
  --offline-scan \
  --skip-dirs reports \
  --no-progress \
  --skip-version-check \
  --timeout 20m \
  .
