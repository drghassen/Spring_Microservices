#!/usr/bin/env bash

set -euo pipefail

source "$(dirname "$0")/lib/application-images.sh"

configure_candidate_images
configure_runtime_environment
create_ci_compose_env_file
trap collect_compose_logs_and_cleanup EXIT
export COMPOSE_REPORT_NAME="container-integration"
mkdir -p reports
ensure_jq
ensure_curl

wait_for_application_stack
run_integration_smoke_checks
