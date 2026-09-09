#!/usr/bin/env bash

set -euo pipefail

source "$(dirname "$0")/lib/application-images.sh"
# shellcheck source=lib/report-evidence.sh
source "$(dirname "$0")/lib/report-evidence.sh"

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

report_trivy_image_evidence() {
  local service
  local report
  local counts
  local high_count
  local critical_count
  local service_status
  local images_scanned=0
  local total_high=0
  local total_critical=0
  local error_count=0
  local failed_count=0
  local gate_status="PASSED"

  report_header "CONTAINER IMAGE SECURITY SUMMARY"
  report_pipeline_context
  report_field "Scope" "Java backend container images"
  report_field "Policy" "HIGH = 0 / CRITICAL = 0"
  printf '\n'
  report_table_header "Service                    HIGH      CRITICAL      Status"

  for service in "${JAVA_SERVICES[@]}"; do
    report="reports/trivy-images/${service}.json"
    high_count="-"
    critical_count="-"
    service_status="ERROR"

    if [[ -s "$report" ]] && jq empty "$report" >/dev/null 2>&1 && \
      jq -e '.ScanError? == null' "$report" >/dev/null 2>&1; then
      if counts="$(jq -er '
        [
          ([.Results[]?.Vulnerabilities[]? | select(.Severity == "HIGH")] | length),
          ([.Results[]?.Vulnerabilities[]? | select(.Severity == "CRITICAL")] | length)
        ] | @tsv
      ' "$report" 2>/dev/null)" && read -r high_count critical_count <<<"$counts" && \
        [[ "$high_count" =~ ^[0-9]+$ && "$critical_count" =~ ^[0-9]+$ ]]; then
        images_scanned=$((images_scanned + 1))
        total_high=$((total_high + high_count))
        total_critical=$((total_critical + critical_count))
        if (( high_count > 0 || critical_count > 0 )); then
          service_status="FAIL"
          failed_count=$((failed_count + 1))
        else
          service_status="PASS"
        fi
      fi
    fi

    if [[ "$service_status" == "ERROR" ]]; then
      error_count=$((error_count + 1))
    fi
    printf '%-25s %8s %13s %11s\n' \
      "$service" "$high_count" "$critical_count" "$service_status"
  done

  report_separator
  printf '\n'
  report_field "Images scanned" "$images_scanned"
  report_field "Images failed" "$failed_count"
  report_field "Technical errors" "$error_count"
  report_field "Total HIGH" "$total_high"
  report_field "Total CRITICAL" "$total_critical"
  report_field "Reports" "reports/trivy-images/*.json"
  if (( error_count > 0 )); then
    gate_status="ERROR"
  elif (( failed_count > 0 )); then
    gate_status="FAILED"
  fi
  case "$gate_status" in
    PASSED) report_field "Action" "None - all scanned images comply with the policy" ;;
    FAILED) report_field "Action" "Remediate the HIGH/CRITICAL findings shown above" ;;
    *) report_field "Action" "Inspect the technical errors and JSON reports" ;;
  esac
  report_field "SECURITY GATE" "$gate_status"
  report_footer
}

finish_trivy_image_scan() {
  local exit_status=$?

  trap - EXIT
  set +e
  report_trivy_image_evidence

  docker volume rm -f "$TRIVY_CACHE_VOLUME" >/dev/null 2>&1 || true
  exit "$exit_status"
}

trap finish_trivy_image_scan EXIT

report_header "DEVSECOPS PIPELINE - CONTAINER IMAGE SECURITY SCAN"
report_pipeline_context
report_field "Security engine" "Trivy"
report_field "Candidate tag" "$IMAGE_TAG"
report_field "Images expected" "${#JAVA_SERVICES[@]}"
report_field "Vulnerability policy" "HIGH = 0 / CRITICAL = 0"
report_field "Final evidence" "Printed at the end of this job"
report_footer

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

echo "Trivy phase 1/3: downloading the vulnerability database."
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

echo "Trivy phase 2/3: downloading the Java vulnerability database."
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
image_scan_index=0
echo "Trivy phase 3/3: scanning candidate container images."
for image in "${image_references[@]}"; do
  image_scan_index=$(( image_scan_index + 1 ))
  service="${image#*/}"
  service="${service%%:*}"
  report="reports/trivy-images/${service}.json"

  printf 'Trivy image %d/%d: service=%s image=%s\n' \
    "$image_scan_index" "${#image_references[@]}" "$service" "$image"

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
