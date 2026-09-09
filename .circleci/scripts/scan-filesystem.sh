#!/usr/bin/env bash

set -euo pipefail

source "$(dirname "$0")/lib/application-images.sh"
# shellcheck source=lib/report-evidence.sh
source "$(dirname "$0")/lib/report-evidence.sh"

readonly TRIVY_IMAGE="aquasec/trivy:0.73.0@sha256:4bbf3824d974b70f27631005e2e6194d4d8fbd6e72c4a9e04cf521e25c5cb07f"
readonly TRIVY_REPORT="reports/trivy-filesystem.json"

ensure_jq
mkdir -p reports .trivy-cache

report_source_security_summary() {
  local counts=""
  local secret_high="NOT AVAILABLE"
  local secret_critical="NOT AVAILABLE"
  local misconfiguration_high="NOT AVAILABLE"
  local misconfiguration_critical="NOT AVAILABLE"
  local dockerfiles_checked="NOT AVAILABLE"
  local summary_status="ERROR"

  if [[ -s "$TRIVY_REPORT" ]] && jq empty "$TRIVY_REPORT" >/dev/null 2>&1; then
    counts="$(jq -r '
      [
        ([.Results[]?.Secrets[]? | select(.Severity == "HIGH")] | length),
        ([.Results[]?.Secrets[]? | select(.Severity == "CRITICAL")] | length),
        ([.Results[]?.Misconfigurations[]? | select(.Severity == "HIGH")] | length),
        ([.Results[]?.Misconfigurations[]? | select(.Severity == "CRITICAL")] | length)
      ] | @tsv
    ' "$TRIVY_REPORT")"
    read -r secret_high secret_critical misconfiguration_high misconfiguration_critical <<<"$counts"
    dockerfiles_checked="$(find . -type f -name Dockerfile | wc -l | tr -d ' ')"
    if (( secret_high == 0 && secret_critical == 0 &&
      misconfiguration_high == 0 && misconfiguration_critical == 0 )); then
      summary_status="PASSED"
    else
      summary_status="FAILED"
    fi
  fi

  report_header "SOURCE SECURITY SUMMARY"
  report_field "Secrets HIGH" "$secret_high"
  report_field "Secrets CRITICAL" "$secret_critical"
  report_field "Dockerfile HIGH" "$misconfiguration_high"
  report_field "Dockerfile CRITICAL" "$misconfiguration_critical"
  report_field "Dockerfiles checked" "$dockerfiles_checked"
  report_field "SOURCE SECURITY GATE" "$summary_status"
  report_footer
  return 0
}

report_header "DEVSECOPS PIPELINE - SOURCE SECURITY SCAN"
report_pipeline_context
report_field "Security engine" "Trivy"
report_field "Source code" "Secret detection"
report_field "Dockerfiles" "Misconfiguration analysis"
report_field "Blocking policy" "HIGH = 0 / CRITICAL = 0"
report_footer

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

report_section "Running source security analysis"
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

report_source_security_summary
gate_high_or_critical_findings
