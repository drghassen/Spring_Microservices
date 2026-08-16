#!/usr/bin/env bash

set -euo pipefail

source "$(dirname "$0")/lib/application-images.sh"

readonly ZAP_IMAGE="ghcr.io/zaproxy/zaproxy@sha256:781a2bdaea47324e7bab583e2263f21d257b0aee61ed51521a5be45f5f5081ef"

configure_candidate_images
ensure_jq
mkdir -p reports/zap

if [[ "${DAST_STACK_READY:-false}" != "true" ]]; then
  configure_runtime_environment
  export COMPOSE_REPORT_NAME="dast"
  trap collect_compose_logs_and_cleanup EXIT
  wait_for_application_stack
else
  : "${COMPOSE_PROJECT_NAME:?COMPOSE_PROJECT_NAME must be set when DAST_STACK_READY=true}"
fi

gate_high_risk_alerts() {
  local target_name="$1"

  [[ -s "reports/zap/${target_name}.json" ]] || {
    echo "ZAP did not create a JSON report for ${target_name}." >&2
    return 1
  }

  jq -e '
    [ .site[]?.alerts[]? | select((.riskcode // "0" | tonumber) >= 3) ] | length == 0
  ' "reports/zap/${target_name}.json" >/dev/null || {
    echo "ZAP reported at least one HIGH-risk alert for ${target_name}." >&2
    return 1
  }
}

zap_baseline() {
  local target_name="$1"
  local target_url="$2"

  docker run --rm \
    --user "$(id -u):$(id -g)" \
    --network "${COMPOSE_PROJECT_NAME}_microservices" \
    -v "$PWD/reports/zap:/zap/wrk" \
    "$ZAP_IMAGE" \
    zap-baseline.py \
    -t "$target_url" \
    -m 2 \
    -I \
    --autooff \
    -J "/zap/wrk/${target_name}.json" \
    -r "/zap/wrk/${target_name}.html"

  gate_high_risk_alerts "$target_name"
}

zap_api_scan() {
  local target_name="$1"
  local specification_url="$2"

  # The OpenAPI documents declare localhost as their server. -O rewrites the
  # hostname AND port to the Compose gateway, allowing ZAP to exercise the
  # real routes from inside the isolated CI network.
  docker run --rm \
    --user "$(id -u):$(id -g)" \
    --network "${COMPOSE_PROJECT_NAME}_microservices" \
    -v "$PWD/reports/zap:/zap/wrk" \
    "$ZAP_IMAGE" \
    zap-api-scan.py \
    -t "$specification_url" \
    -f openapi \
    -O gateway:8222 \
    -T 10 \
    -I \
    -J "/zap/wrk/${target_name}.json" \
    -r "/zap/wrk/${target_name}.html"

  gate_high_risk_alerts "$target_name"
}

dast_scan_failed=0

if ! zap_baseline client http://client:8080/; then
  dast_scan_failed=1
fi

if ! zap_baseline gateway http://gateway:8222/actuator/health; then
  dast_scan_failed=1
fi

for api in users games library order payment; do
  if ! zap_api_scan "${api}-api" "http://gateway:8222/${api}/v3/api-docs"; then
    dast_scan_failed=1
  fi
done

if (( dast_scan_failed )); then
  echo "OWASP ZAP reported at least one HIGH-risk alert." >&2
  exit 1
fi