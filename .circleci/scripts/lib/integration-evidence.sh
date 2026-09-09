#!/usr/bin/env bash

set -euo pipefail

# shellcheck source=report-evidence.sh
source "$(dirname "${BASH_SOURCE[0]}")/report-evidence.sh"

declare -Ag INTEGRATION_EVIDENCE_RESULTS=(
  ["Application stack"]="NOT RUN"
  ["Health checks"]="NOT RUN"
  ["Eureka / service registration"]="NOT RUN"
  ["Smoke tests"]="NOT RUN"
  ["Gateway availability"]="NOT RUN"
)
INTEGRATION_EVIDENCE_PRINTED=0

integration_evidence_check_started() {
  local check="$1"

  INTEGRATION_EVIDENCE_RESULTS["$check"]="FAIL"
}

integration_evidence_check_passed() {
  local check="$1"

  INTEGRATION_EVIDENCE_RESULTS["$check"]="PASS"
}

report_integration_evidence() {
  local check
  local result
  local integration_result="PASSED"
  local -a checks=(
    "Application stack"
    "Health checks"
    "Eureka / service registration"
    "Smoke tests"
    "Gateway availability"
  )

  (( INTEGRATION_EVIDENCE_PRINTED == 0 )) || return 0
  INTEGRATION_EVIDENCE_PRINTED=1

  report_header "MICROSERVICES INTEGRATION TEST SUMMARY"
  report_pipeline_context
  printf '\n'
  report_table_header "Check                                             Result"
  for check in "${checks[@]}"; do
    result="${INTEGRATION_EVIDENCE_RESULTS[$check]}"
    printf '%-49s %s\n' "$check" "$result"
    [[ "$result" == "PASS" ]] || integration_result="FAILED"
  done
  report_separator
  printf '\n'
  report_field "INTEGRATION RESULT" "$integration_result"
  report_footer
}

finish_container_integration() {
  local exit_status=$?

  trap - EXIT
  set +e
  report_integration_evidence
  collect_compose_logs_and_cleanup
  exit "$exit_status"
}
