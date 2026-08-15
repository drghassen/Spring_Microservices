#!/usr/bin/env bash

set -euo pipefail

source "$(dirname "$0")/lib/application-images.sh"

configure_candidate_images
configure_runtime_environment
ensure_jq
export COMPOSE_REPORT_NAME="runtime-security"
mkdir -p reports
trap collect_compose_logs_and_cleanup EXIT

wait_for_application_stack

# Keep the same containers alive for DAST. Recreating the full microservice
# stack between smoke checks and ZAP roughly doubles this slowest CI stage.
export DAST_STACK_READY=true
bash "$(dirname "$0")/run-dast.sh"
