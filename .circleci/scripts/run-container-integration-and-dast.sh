#!/usr/bin/env bash

set -euo pipefail

source "$(dirname "$0")/lib/application-images.sh"
# shellcheck source=lib/integration-evidence.sh
source "$(dirname "$0")/lib/integration-evidence.sh"

configure_candidate_images
configure_runtime_environment
create_ci_compose_env_file
trap finish_container_integration EXIT
export COMPOSE_REPORT_NAME="container-integration-dast"
mkdir -p reports
ensure_jq
ensure_curl

report_header "DEVSECOPS PIPELINE - INTEGRATION TESTS & OWASP ZAP"
report_pipeline_context
report_field "Runtime" "Docker Compose"
report_field "Candidate tag" "$IMAGE_TAG"
report_field "Integration" "Health, Eureka registration, smoke tests, Gateway"
report_field "DAST" "Frontend, Gateway and authenticated service APIs"
report_footer

run_timed_step "application stack startup" wait_for_application_stack
run_timed_step "integration smoke checks" run_integration_smoke_checks
report_integration_evidence

use_ci_dast_fixture_credentials
run_timed_step "complete DAST phase" env DAST_STACK_READY=true \
  bash .circleci/scripts/run-dast.sh
