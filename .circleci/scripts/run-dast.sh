#!/usr/bin/env bash

set -euo pipefail

source "$(dirname "$0")/lib/application-images.sh"

readonly ZAP_IMAGE="ghcr.io/zaproxy/zaproxy@sha256:781a2bdaea47324e7bab583e2263f21d257b0aee61ed51521a5be45f5f5081ef"

configure_candidate_images
configure_runtime_environment
ensure_jq
export COMPOSE_REPORT_NAME="dast"
mkdir -p reports/zap
trap collect_compose_logs_and_cleanup EXIT

wait_for_application_stack

zap_baseline() {
  local target_name="$1"
  local target_url="$2"

  docker run --rm \
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

  jq -e '
    [ .site[]?.alerts[]? | select((.riskcode // "0" | tonumber) >= 3) ] | length == 0
  ' "reports/zap/${target_name}.json" >/dev/null || {
    echo "ZAP reported at least one HIGH-risk alert for ${target_name}." >&2
    exit 1
  }
}

zap_baseline client http://client:8080/
zap_baseline gateway http://gateway:8222/actuator/health
