#!/usr/bin/env bash

set -euo pipefail

source "$(dirname "$0")/lib/application-images.sh"
# shellcheck source=lib/integration-evidence.sh
source "$(dirname "$0")/lib/integration-evidence.sh"

configure_candidate_images
configure_runtime_environment
create_ci_compose_env_file
trap finish_container_integration EXIT
export COMPOSE_REPORT_NAME="container-integration"
mkdir -p reports
ensure_jq
ensure_curl

report_header "DEVSECOPS PIPELINE - MICROSERVICES INTEGRATION TESTS"
report_pipeline_context
report_field "Runtime" "Docker Compose"
report_field "Candidate tag" "$IMAGE_TAG"
report_field "Checks" "Health, Eureka registration, smoke tests, Gateway"
report_footer

wait_for_application_stack
run_integration_smoke_checks
