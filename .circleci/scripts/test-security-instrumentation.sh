#!/usr/bin/env bash

set -Eeuo pipefail

readonly REPOSITORY_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
readonly IMAGE_LIBRARY="${REPOSITORY_ROOT}/.circleci/scripts/lib/application-images.sh"
readonly DTRACK_SCRIPT="${REPOSITORY_ROOT}/.circleci/scripts/publish-sboms-dependency-track.sh"
readonly DAST_SCRIPT="${REPOSITORY_ROOT}/.circleci/scripts/run-dast.sh"
readonly CONTINUE_CONFIG="${REPOSITORY_ROOT}/.circleci/continue-config.yml"

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
  [[ "$output" == *"Timing: safe timing label = "* ]] || return 1
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

  [[ "${#APP_SERVICES[@]}" -eq 9 ]] || return 1
  [[ "${APP_SERVICES[*]}" == "${expected_services[*]}" ]] || return 1
  grep -Fq 'for service in "${APP_SERVICES[@]}"; do' "$DTRACK_SCRIPT"
}

test_authentication_precedes_api_scans() {
  local authentication_line
  local api_batch_line
  local frontend_line
  local gateway_line

  authentication_line="$(grep -n -m1 'if configure_dast_jwt_token; then' "$DAST_SCRIPT" | cut -d: -f1)"
  api_batch_line="$(grep -n -m1 'if ! run_authenticated_api_batch; then' "$DAST_SCRIPT" | cut -d: -f1)"
  frontend_line="$(grep -n -m1 'if ! zap_frontend_full_scan client' "$DAST_SCRIPT" | cut -d: -f1)"
  gateway_line="$(grep -n -m1 'if ! zap_baseline gateway' "$DAST_SCRIPT" | cut -d: -f1)"
  (( frontend_line < gateway_line )) || return 1
  (( gateway_line < authentication_line )) || return 1
  (( authentication_line < api_batch_line ))
}

test_high_findings_still_fail() {
  grep -Fq 'SECURITY_FINDINGS_HIGH+=("${target_name}: high_count=${high_count}")' "$DAST_SCRIPT" || return 1
  grep -Fq 'record_security_high "$target_name" "$high_count"' "$DAST_SCRIPT" || return 1
  grep -Fq 'if (( dast_scan_failed )); then' "$DAST_SCRIPT" || return 1
  grep -Fq 'return 1' "$DAST_SCRIPT"
}

test_scan_errors_still_fail() {
  grep -Fq 'SCAN_ERRORS+=("${target_name}: ${reason}")' "$DAST_SCRIPT" || return 1
  grep -Fq 'ZAP command failed before a reliable security result was available' "$DAST_SCRIPT" || return 1
  grep -Fq 'dast_scan_failed=1' "$DAST_SCRIPT" || return 1
  grep -Fq 'return 1' "$DAST_SCRIPT"
}

validate_parallelism_value() {
  local value="$1"

  DAST_API_PARALLELISM="$value" bash -c '
    set -Eeuo pipefail
    source "$1"
    validate_dast_api_parallelism
  ' _ "$DAST_SCRIPT"
}

test_parallelism_default_and_validation() {
  local value

  bash -c '
    set -Eeuo pipefail
    unset DAST_API_PARALLELISM
    source "$1"
    [[ "$DAST_API_PARALLELISM" == "3" ]]
  ' _ "$DAST_SCRIPT" || return 1
  for value in 1 2 3; do
    validate_parallelism_value "$value" || return 1
  done
  for value in 0 4 5 invalid 2.5; do
    if validate_parallelism_value "$value" >/dev/null 2>&1; then
      return 1
    fi
  done
}

run_mock_api_batch() {
  local work_directory="$1"
  local parallelism="$2"
  local failed_api="${3:-}"
  local high_api="${4:-}"

  DAST_API_PARALLELISM="$parallelism" \
  MOCK_FAILED_API="$failed_api" \
  MOCK_HIGH_API="$high_api" \
  DAST_JWT_TOKEN="mock.jwt.value" \
  DAST_AUTH_PASSWORD="mock-password-value" \
  MOCK_AUTHORIZATION_HEADER="Bearer mock.jwt.value" \
    bash -s -- "$DAST_SCRIPT" "$work_directory" <<'BASH'
set -Eeuo pipefail

readonly dast_script="$1"
readonly work_directory="$2"
cd "$work_directory"
source "$dast_script"

readonly mock_state="${work_directory}/mock-state"
mkdir -p "$mock_state"
printf '0\n' > "${mock_state}/active"
printf '0\n' > "${mock_state}/max-active"
: > "${mock_state}/executions"
: > "${mock_state}/events"

report_api_batch_resources() {
  printf '%s\n' "$1" >> "${mock_state}/resource-phases"
}

update_mock_concurrency() {
  local operation="$1"
  local api="$2"
  local active
  local maximum

  exec 9>>"${mock_state}/counter.lock"
  flock 9
  active="$(<"${mock_state}/active")"
  maximum="$(<"${mock_state}/max-active")"
  if [[ "$operation" == "start" ]]; then
    active=$(( active + 1 ))
    (( active <= DAST_API_PARALLELISM )) || exit 91
    (( active > maximum )) && maximum="$active"
    printf '%s\n' "$api" >> "${mock_state}/executions"
  else
    active=$(( active - 1 ))
  fi
  printf '%s\n' "$active" > "${mock_state}/active"
  printf '%s\n' "$maximum" > "${mock_state}/max-active"
  printf '%s %s\n' "$operation" "$api" >> "${mock_state}/events"
  flock -u 9
}

zap_api_scan() {
  local target_name="$1"
  local api="${target_name%-api}"

  update_mock_concurrency start "$api"
  case "$api" in
    users) sleep 0.08 ;;
    games|library) sleep 0.30 ;;
    *) sleep 0.04 ;;
  esac
  update_mock_concurrency finish "$api"

  if [[ "$api" == "${MOCK_FAILED_API:-}" ]]; then
    record_scan_error "$target_name" "mock scan execution failure"
    return 7
  fi
  if [[ "$api" == "${MOCK_HIGH_API:-}" ]]; then
    record_security_high "$target_name" 1
    return 1
  fi
  return 0
}

batch_status=0
run_authenticated_api_batch || batch_status=$?
printf '%s\n' "$batch_status" > "${mock_state}/batch-status"
exit "$batch_status"
BASH
}

assert_all_apis_executed_once() {
  local execution_file="$1"
  local expected_file

  expected_file="$(mktemp)"
  printf '%s\n' games library order payment users > "$expected_file"
  if ! LC_ALL=C sort "$execution_file" | uniq -c | awk '{print $2}' | diff -u "$expected_file" -; then
    rm -f -- "$expected_file"
    return 1
  fi
  if [[ "$(wc -l < "$execution_file")" -ne 5 ]]; then
    rm -f -- "$expected_file"
    return 1
  fi
  rm -f -- "$expected_file"
}

test_parallelism_one_is_sequential() {
  local work_directory

  work_directory="$(mktemp -d)"
  if ! run_mock_api_batch "$work_directory" 1 >"${work_directory}/output" 2>&1; then
    rm -rf -- "$work_directory"
    return 1
  fi
  if [[ "$(<"${work_directory}/mock-state/max-active")" != "1" ]] || \
    ! assert_all_apis_executed_once "${work_directory}/mock-state/executions"; then
    rm -rf -- "$work_directory"
    return 1
  fi
  rm -rf -- "$work_directory"
}

test_bounded_pool_reaches_three_and_refills() {
  local work_directory
  local order_start
  local games_finish
  local library_finish

  work_directory="$(mktemp -d)"
  if ! run_mock_api_batch "$work_directory" 3 >"${work_directory}/output" 2>&1; then
    rm -rf -- "$work_directory"
    return 1
  fi
  if [[ "$(<"${work_directory}/mock-state/max-active")" != "3" ]] || \
    ! assert_all_apis_executed_once "${work_directory}/mock-state/executions"; then
    rm -rf -- "$work_directory"
    return 1
  fi
  order_start="$(grep -n -m1 '^start order$' "${work_directory}/mock-state/events" | cut -d: -f1)"
  games_finish="$(grep -n -m1 '^finish games$' "${work_directory}/mock-state/events" | cut -d: -f1)"
  library_finish="$(grep -n -m1 '^finish library$' "${work_directory}/mock-state/events" | cut -d: -f1)"
  if (( order_start >= games_finish || order_start >= library_finish )); then
    rm -rf -- "$work_directory"
    return 1
  fi
  rm -rf -- "$work_directory"
}

test_failed_worker_runs_every_api_and_fails_batch() {
  local work_directory

  work_directory="$(mktemp -d)"
  if run_mock_api_batch "$work_directory" 3 users >"${work_directory}/output" 2>&1; then
    rm -rf -- "$work_directory"
    return 1
  fi
  if [[ "$(<"${work_directory}/mock-state/batch-status")" == "0" ]] || \
    ! assert_all_apis_executed_once "${work_directory}/mock-state/executions" || \
    [[ "$(find "${work_directory}/reports/zap/api-worker-results" -maxdepth 1 -name '*.json' | wc -l)" -ne 5 ]]; then
    rm -rf -- "$work_directory"
    return 1
  fi
  rm -rf -- "$work_directory"
}

test_high_worker_fails_batch() {
  local work_directory

  work_directory="$(mktemp -d)"
  if run_mock_api_batch "$work_directory" 3 '' users >"${work_directory}/output" 2>&1; then
    rm -rf -- "$work_directory"
    return 1
  fi
  if ! jq -e '.api == "users" and .scan_success == true and .high_count == 1 and .exit_code == 1' \
    "${work_directory}/reports/zap/api-worker-results/users.json" >/dev/null || \
    ! grep -Fq 'SECURITY_FINDING_HIGH: users-api: high_count=1' "${work_directory}/output"; then
    rm -rf -- "$work_directory"
    return 1
  fi
  rm -rf -- "$work_directory"
}

test_successful_batch_and_result_secrecy() {
  local work_directory

  work_directory="$(mktemp -d)"
  if ! run_mock_api_batch "$work_directory" 3 >"${work_directory}/output" 2>&1; then
    rm -rf -- "$work_directory"
    return 1
  fi
  if [[ "$(<"${work_directory}/mock-state/batch-status")" != "0" ]] || \
    ! grep -Fq 'Timing: authenticated API parallel batch = ' "${work_directory}/output" || \
    ! grep -Fq 'before' "${work_directory}/mock-state/resource-phases" || \
    ! grep -Fq 'after' "${work_directory}/mock-state/resource-phases" || \
    grep -R -E 'mock\.jwt\.value|mock-password-value|Authorization|Bearer' \
      "${work_directory}/reports/zap/api-worker-results" "${work_directory}/output" || \
    ! jq -e '
    (keys | sort) == (["api", "elapsed_seconds", "exit_code", "high_count", "scan_success"] | sort)
  ' "${work_directory}/reports/zap/api-worker-results/"*.json >/dev/null; then
    rm -rf -- "$work_directory"
    return 1
  fi
  rm -rf -- "$work_directory"
}

run_mock_aggregation() {
  local work_directory="$1"
  local scenario="$2"

  bash -s -- "$DAST_SCRIPT" "$work_directory" "$scenario" <<'BASH'
set -Eeuo pipefail

readonly dast_script="$1"
readonly work_directory="$2"
readonly scenario="$3"
cd "$work_directory"
source "$dast_script"
prepare_api_worker_result_dir

for api in "${AUTHENTICATED_APIS[@]}"; do
  write_api_worker_result "$api" true 0 0 1
  API_WORKER_STATUS_BY_API["$api"]=0
done

case "$scenario" in
  missing)
    rm -f -- "${API_WORKER_RESULT_DIR}/users.json"
    ;;
  malformed)
    printf '%s\n' '{not-json' > "${API_WORKER_RESULT_DIR}/users.json"
    ;;
  duplicate)
    cp "${API_WORKER_RESULT_DIR}/users.json" "${API_WORKER_RESULT_DIR}/users-copy.json"
    ;;
esac

aggregate_api_worker_results
BASH
}

test_invalid_worker_results_fail() {
  local scenario
  local work_directory

  for scenario in missing malformed duplicate; do
    work_directory="$(mktemp -d)"
    if run_mock_aggregation "$work_directory" "$scenario" >/dev/null 2>&1; then
      rm -rf -- "$work_directory"
      return 1
    fi
    rm -rf -- "$work_directory"
  done
}

test_duplicate_worker_write_is_rejected() {
  local work_directory

  work_directory="$(mktemp -d)"
  if ! bash -s -- "$DAST_SCRIPT" "$work_directory" <<'BASH'
set -Eeuo pipefail
cd "$2"
source "$1"
prepare_api_worker_result_dir
write_api_worker_result users true 0 0 1
if write_api_worker_result users true 0 0 1; then
  exit 1
fi
BASH
  then
    rm -rf -- "$work_directory"
    return 1
  fi
  rm -rf -- "$work_directory"
}

test_worker_output_paths_are_unique() {
  bash -c '
    set -Eeuo pipefail
    source "$1"
    validate_unique_api_output_paths
    mapfile -t paths < <(for api in "${AUTHENTICATED_APIS[@]}"; do api_output_paths "$api"; done)
    [[ "${#paths[@]}" -eq 25 ]]
    [[ "$(printf "%s\n" "${paths[@]}" | LC_ALL=C sort -u | wc -l)" -eq 25 ]]
  ' _ "$DAST_SCRIPT"
}

test_cleanup_and_resource_diagnostics_remain() {
  grep -Fq "trap 'handle_dast_signal 130' INT" "$DAST_SCRIPT" || return 1
  grep -Fq "trap 'handle_dast_signal 143' TERM" "$DAST_SCRIPT" || return 1
  grep -Fq 'trap finish_dast EXIT' "$DAST_SCRIPT" || return 1
  grep -Fq 'terminate_api_workers' "$DAST_SCRIPT" || return 1
  grep -Fq 'docker rm --force "$container_name"' "$DAST_SCRIPT" || return 1
  grep -Fq 'docker stats --no-stream' "$DAST_SCRIPT" || return 1
  grep -Fq 'free -h' "$DAST_SCRIPT" || return 1
  grep -Fq 'nproc || true' "$DAST_SCRIPT" || return 1
  bash -c '
    set -Eeuo pipefail
    source "$1"
    docker() { return 0; }
    sleep 30 &
    worker_pid=$!
    trap '\''kill "$worker_pid" 2>/dev/null || true; wait "$worker_pid" 2>/dev/null || true'\'' EXIT
    API_WORKER_PIDS=("$worker_pid")
    API_WORKER_API_BY_PID["$worker_pid"]="users"
    terminate_api_workers
    ! kill -0 "$worker_pid" 2>/dev/null
    trap - EXIT
  ' _ "$DAST_SCRIPT"
}

test_application_security_gate_dag() {
  python3 - "$CONTINUE_CONFIG" <<'PY'
import sys

try:
    import yaml
except ImportError as error:
    raise SystemExit("PyYAML is required for the CircleCI DAG regression test") from error

with open(sys.argv[1], encoding="utf-8") as config_file:
    config = yaml.safe_load(config_file)

workflow_jobs = config["workflows"]["application-ci"]["jobs"]
jobs = {}
for entry in workflow_jobs:
    if isinstance(entry, str):
        jobs[entry] = {}
    elif isinstance(entry, dict) and len(entry) == 1:
        name, job_config = next(iter(entry.items()))
        jobs[name] = job_config or {}
    else:
        raise AssertionError(f"unexpected application-ci job entry: {entry!r}")

def requires(job_name):
    required_jobs = jobs[job_name].get("requires", [])
    if not isinstance(required_jobs, list):
        raise AssertionError(f"{job_name} requires must be a list")
    return set(required_jobs)

assert requires("dependency-track-sbom-publish") == {"image-trivy-scan"}
assert requires("container-integration-dast") == {"image-trivy-scan"}
assert "dependency-track-sbom-publish" not in requires("container-integration-dast")
assert requires("release-acr") == {
    "dependency-track-sbom-publish",
    "container-integration-dast",
    "qualify-database-migrations-image",
}
assert requires("aca-preflight") == {"release-acr"}
PY
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
test_parallelism_default_and_validation || fail "DAST API parallelism defaults to three and validates one through three"
pass "DAST API parallelism defaults to three and validates one through three"
test_parallelism_one_is_sequential || fail "DAST API parallelism one is sequential"
pass "DAST API parallelism one is sequential"
test_bounded_pool_reaches_three_and_refills || fail "bounded API pool reaches three and refills immediately"
pass "bounded API pool reaches three and refills immediately"
test_failed_worker_runs_every_api_and_fails_batch || fail "failed API worker does not prevent all five scans"
pass "failed API worker does not prevent all five scans"
test_high_worker_fails_batch || fail "HIGH API result fails the batch"
pass "HIGH API result fails the batch"
test_successful_batch_and_result_secrecy || fail "successful API batch is complete and credential-free"
pass "successful API batch is complete and credential-free"
test_invalid_worker_results_fail || fail "missing, malformed, and duplicate results fail"
pass "missing, malformed, and duplicate results fail"
test_duplicate_worker_write_is_rejected || fail "duplicate worker result writes are rejected"
pass "duplicate worker result writes are rejected"
test_worker_output_paths_are_unique || fail "every authenticated API worker output path is unique"
pass "every authenticated API worker output path is unique"
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
test_cleanup_and_resource_diagnostics_remain || fail "worker cleanup, signal traps, and resource diagnostics remain"
pass "worker cleanup, signal traps, and resource diagnostics remain"
test_application_security_gate_dag || fail "application security gate DAG remains fail-closed"
pass "application security gate DAG remains fail-closed"

printf 'Security instrumentation suite passed: %s checks.\n' "$TEST_COUNT"
