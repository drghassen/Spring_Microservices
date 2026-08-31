#!/usr/bin/env bash

set -euo pipefail

source "$(dirname "$0")/lib/application-images.sh"

configure_candidate_images
configure_runtime_environment
create_ci_compose_env_file
trap collect_compose_logs_and_cleanup EXIT
export COMPOSE_REPORT_NAME="container-integration-dast"
mkdir -p reports
ensure_jq
ensure_curl

run_timed_step "application stack startup" wait_for_application_stack
run_timed_step "integration smoke checks" run_integration_smoke_checks

use_ci_dast_fixture_credentials
run_timed_step "complete DAST phase" env DAST_STACK_READY=true \
  bash .circleci/scripts/run-dast.sh
