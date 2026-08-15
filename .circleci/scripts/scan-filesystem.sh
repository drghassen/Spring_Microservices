#!/usr/bin/env bash

set -euo pipefail

source "$(dirname "$0")/lib/application-images.sh"

readonly TRIVY_IMAGE="aquasec/trivy:0.73.0@sha256:4bbf3824d974b70f27631005e2e6194d4d8fbd6e72c4a9e04cf521e25c5cb07f"
readonly TRIVY_REPORT="reports/trivy-filesystem.json"

ensure_jq
mkdir -p reports .trivy-cache

trivy() {
  docker run --rm \
    -v "$PWD:/workspace" \
    -w /workspace \
    -v "$PWD/.trivy-cache:/root/.cache/" \
    "$TRIVY_IMAGE" "$@"
}

gate_high_or_critical_findings() {
  [[ -s "$TRIVY_REPORT" ]] || {
    echo "Trivy did not create a filesystem JSON report." >&2
    return 1
  }

  jq empty "$TRIVY_REPORT" >/dev/null 2>&1 || {
    echo "Trivy created an invalid filesystem JSON report." >&2
    return 1
  }

  jq -e '
    [
      .Results[]?
      | ((.Misconfigurations // []) + (.Secrets // []))[]
      | select(.Severity == "HIGH" or .Severity == "CRITICAL")
    ] | length == 0
  ' "$TRIVY_REPORT" >/dev/null || {
    echo "Trivy reported at least one HIGH or CRITICAL filesystem finding." >&2
    return 1
  }
}

trivy fs \
  --scanners secret,misconfig \
  --misconfig-scanners dockerfile \
  --severity HIGH,CRITICAL \
  --exit-code 0 \
  --format json \
  --output "$TRIVY_REPORT" \
  --offline-scan \
  --skip-dirs reports \
  --no-progress \
  --skip-version-check \
  --timeout 20m \
  .

gate_high_or_critical_findings
