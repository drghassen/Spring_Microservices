#!/usr/bin/env bash

set -Eeuo pipefail

readonly REPOSITORY_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
readonly IMAGE_LIBRARY="${REPOSITORY_ROOT}/.circleci/scripts/lib/application-images.sh"
readonly DTRACK_SCRIPT="${REPOSITORY_ROOT}/.circleci/scripts/publish-sboms-dependency-track.sh"
readonly DAST_SCRIPT="${REPOSITORY_ROOT}/.circleci/scripts/run-dast.sh"

# shellcheck source-path=SCRIPTDIR
# shellcheck source=lib/application-images.sh
source "$IMAGE_LIBRARY"

TEST_COUNT=0

pass() {
  TEST_COUNT=$(( TEST_COUNT + 1 ))
  printf 'PASS: %s\n' "$1"
}

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

assert_file_contains() {
  local description="$1"
  local expected="$2"
  local file="$3"

  grep -Fq -- "$expected" "$file" || fail "$description"
  pass "$description"
}

timed_success() {
  return 0
}

timed_failure() {
  return 37
}

timed_quiet_success() {
  local ignored_argument="$1"
  : "$ignored_argument"
}

test_timed_success() {
  run_timed_step "successful timing test" timed_success >/dev/null
}

test_timed_failure_status() {
  local status

  if run_timed_step "failed timing test" timed_failure >/dev/null; then
    return 1
  else
    status=$?
  fi
  [[ "$status" -eq 37 ]]
}

test_timing_hides_arguments() {
  local secret_argument="timing-secret-must-not-appear"
  local output

  output="$(run_timed_step "safe timing label" timed_quiet_success "$secret_argument" 2>&1)"
  [[ "$output" == *"Timing: safe timing label = "* ]]
  [[ "$output" != *"$secret_argument"* ]]
}

test_timing_retains_errexit() {
  local output
  local output_file

  output_file="$(mktemp)"
  if bash -c '
    set -Eeuo pipefail
    source "$1"
    timed_errexit_failure() {
      false
      printf "unreachable after errexit failure\\n"
    }
    run_timed_step "errexit timing test" timed_errexit_failure
  ' _ "$IMAGE_LIBRARY" >"$output_file" 2>&1; then
    rm -f -- "$output_file"
    return 1
  fi
  output="$(<"$output_file")"
  rm -f -- "$output_file"
  [[ "$output" != *"unreachable after errexit failure"* ]]
}

test_all_runtime_sboms_remain() {
  local -a expected_services=(
    config-server discovery-service gateway games-service library-service
    order-service payment-service user-service client
  )

  [[ "${#APP_SERVICES[@]}" -eq 9 ]]
  [[ "${APP_SERVICES[*]}" == "${expected_services[*]}" ]]
  grep -Fq 'for service in "${APP_SERVICES[@]}"; do' "$DTRACK_SCRIPT"
}

test_authenticated_api_scans_are_sequential() {
  local api_scan_line

  grep -Fq 'for api in users games library order payment; do' "$DAST_SCRIPT"
  api_scan_line="$(grep -F 'if ! zap_api_scan "${api}-api"' "$DAST_SCRIPT")"
  [[ "$api_scan_line" != *'&'* ]]
  ! grep -Fq 'DAST_API_PARALLELISM' "$DAST_SCRIPT"
}

test_authentication_precedes_api_scans() {
  local authentication_line
  local api_loop_line

  authentication_line="$(grep -n -m1 'if configure_dast_jwt_token; then' "$DAST_SCRIPT" | cut -d: -f1)"
  api_loop_line="$(grep -n -m1 'for api in users games library order payment; do' "$DAST_SCRIPT" | cut -d: -f1)"
  (( authentication_line < api_loop_line ))
  grep -Fq 'if (( auth_ready )); then' "$DAST_SCRIPT"
}

test_high_findings_still_fail() {
  grep -Fq 'SECURITY_FINDINGS_HIGH+=("${target_name}: high_count=${high_count}")' "$DAST_SCRIPT"
  grep -Fq 'record_security_high "$target_name" "$high_count"' "$DAST_SCRIPT"
  grep -Fq 'if (( dast_scan_failed )); then' "$DAST_SCRIPT"
  grep -Fq 'exit 1' "$DAST_SCRIPT"
}

test_scan_errors_still_fail() {
  grep -Fq 'SCAN_ERRORS+=("${target_name}: ${reason}")' "$DAST_SCRIPT"
  grep -Fq 'ZAP command failed before a reliable security result was available' "$DAST_SCRIPT"
  grep -Fq 'dast_scan_failed=1' "$DAST_SCRIPT"
  grep -Fq 'exit 1' "$DAST_SCRIPT"
}

test_timed_success || fail "timed successful function returns zero"
pass "timed successful function returns zero"
test_timed_failure_status || fail "timed failed function preserves its status"
pass "timed failed function preserves its status"
test_timing_hides_arguments || fail "timing output hides function arguments"
pass "timing output hides function arguments"
test_timing_retains_errexit || fail "timed functions retain errexit behavior"
pass "timed functions retain errexit behavior"

assert_file_contains "DTrack parallelism remains three" \
  'readonly DTRACK_PARALLELISM="${DTRACK_PARALLELISM:-3}"' "$DTRACK_SCRIPT"
test_all_runtime_sboms_remain || fail "all nine runtime application SBOMs remain"
pass "all nine runtime application SBOMs remain"
test_authenticated_api_scans_are_sequential || fail "all five authenticated API scans remain sequential"
pass "all five authenticated API scans remain sequential"
assert_file_contains "frontend full scan remains" \
  'if ! zap_frontend_full_scan client "$CLIENT_TARGET_URL"; then' "$DAST_SCRIPT"
assert_file_contains "Gateway baseline remains" \
  'if ! zap_baseline gateway "$GATEWAY_HEALTH_URL"; then' "$DAST_SCRIPT"
test_authentication_precedes_api_scans || fail "authentication remains required before API scans"
pass "authentication remains required before API scans"
test_high_findings_still_fail || fail "HIGH findings still fail DAST"
pass "HIGH findings still fail DAST"
test_scan_errors_still_fail || fail "scan execution errors still fail DAST"
pass "scan execution errors still fail DAST"

printf 'Security instrumentation suite passed: %s checks.\n' "$TEST_COUNT"
