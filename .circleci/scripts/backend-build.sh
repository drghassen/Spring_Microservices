#!/usr/bin/env bash

set -euo pipefail

# shellcheck source=lib/report-evidence.sh
source "$(dirname "$0")/lib/report-evidence.sh"

readonly BACKEND_MODULES=(
  database-migrations config-server discovery-service gateway games-service
  library-service order-service payment-service user-service
)

report_header "DEVSECOPS PIPELINE - BACKEND BUILD & TEST"
report_pipeline_context
report_field "Build tool" "Apache Maven"
report_field "Lifecycle" "clean verify"
report_field "Reactor modules" "${#BACKEND_MODULES[@]}"
printf '[BUILD] Modules: %s\n' "${BACKEND_MODULES[*]}"
report_footer

report_section "Running Maven compilation and tests"
mvn -B -ntp clean verify

report_header "BACKEND BUILD & TEST SUMMARY"
report_field "Modules processed" "${#BACKEND_MODULES[@]}"
report_field "Compilation" "PASSED"
report_field "Tests" "PASSED"
report_field "Maven verification" "PASSED"
report_field "RESULT" "BACKEND BUILD & TEST PASSED"
report_footer
