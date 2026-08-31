#!/usr/bin/env bash

set -euo pipefail

readonly SCRIPT_DIRECTORY="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly FILTER_SCRIPT="${SCRIPT_DIRECTORY}/filter-azure-rg-findings.py"
readonly ORCHESTRATOR="${SCRIPT_DIRECTORY}/run-scheduled-rg-scan.sh"
readonly MOCK_DISPATCHER="${SCRIPT_DIRECTORY}/tests/mock-command.sh"
readonly SUBSCRIPTION_ID="00000000-0000-0000-0000-000000000001"
readonly TEST_TOKEN="test-token-that-must-never-be-logged"
readonly TEST_DD_TEST_ID="2468"

test_directory="$(mktemp -d)"
cleanup() {
  if [[ "$test_directory" == /tmp/tmp.* && -d "$test_directory" ]]; then
    rm -rf -- "$test_directory"
  fi
}
trap cleanup EXIT

tests_run=0
pass() {
  tests_run=$((tests_run + 1))
  printf 'PASS: %s\n' "$1"
}
fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}
assert_not_called() {
  [[ ! -e "$1" ]] || fail "$2"
}

mock_bin="${test_directory}/bin"
mkdir -p "$mock_bin"
ln -s "$MOCK_DISPATCHER" "${mock_bin}/az"
ln -s "$MOCK_DISPATCHER" "${mock_bin}/prowler"
ln -s "$MOCK_DISPATCHER" "${mock_bin}/curl"
ln -s "$MOCK_DISPATCHER" "${mock_bin}/python"

inventory="${test_directory}/inventory.json"
printf '%s\n' \
  '[{"id":"/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/internship_proxym/providers/Microsoft.Network/virtualNetworks/main"}]' \
  >"$inventory"

valid_csv="${test_directory}/valid.csv"
printf '%s\n' \
  'CHECK_ID;PROVIDER;STATUS;SEVERITY;RESOURCE_UID' \
  'target;azure;FAIL;high;/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/INTERNSHIP_PROXYM/providers/Microsoft.Network/virtualNetworks/main/subnets/default' \
  'same_rg_not_inventory;azure;FAIL;medium;/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/internship_proxym/providers/Microsoft.Storage/storageAccounts/unlisted' \
  'other_rg;azure;FAIL;medium;/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/elsewhere/providers/Microsoft.Network/virtualNetworks/main' \
  'subscription;azure;FAIL;low;/subscriptions/00000000-0000-0000-0000-000000000001' \
  'entra;azure;FAIL;critical;11111111-1111-1111-1111-111111111111' \
  >"$valid_csv"

filtered_csv="${test_directory}/filtered.csv"
metadata_json="${test_directory}/metadata.json"
python3 "$FILTER_SCRIPT" \
  --input-csv "$valid_csv" \
  --inventory-json "$inventory" \
  --resource-group internship_proxym \
  --output-csv "$filtered_csv" \
  --metadata-json "$metadata_json" \
  --timestamp 2026-08-31T00:00:00Z \
  --subscription-id "$SUBSCRIPTION_ID" >/dev/null
python3 - "$filtered_csv" "$metadata_json" <<'PY' || fail "scope filter validation"
import csv
import json
import sys

with open(sys.argv[1], encoding="utf-8", newline="") as report_file:
    rows = list(csv.DictReader(report_file, delimiter=";", strict=True))
assert [row["CHECK_ID"] for row in rows] == ["target"]
with open(sys.argv[2], encoding="utf-8") as metadata_file:
    metadata = json.load(metadata_file)
assert metadata["azure_resource_count"] == 1
assert metadata["full_prowler_finding_count"] == 5
assert metadata["filtered_rg_finding_count"] == 1
assert metadata["severity_counts"] == {
    "critical": 0,
    "high": 1,
    "medium": 0,
    "low": 0,
}
assert metadata["scan_success_status"] == "SUCCESS"
PY
pass "target RG descendant survives; other RG, unlisted RG resource, subscription, and Entra rows are rejected"

malformed_csv="${test_directory}/malformed.csv"
printf '%s\n' \
  'CHECK_ID;PROVIDER;STATUS;SEVERITY' \
  'bad;azure;FAIL;high' >"$malformed_csv"
if python3 "$FILTER_SCRIPT" \
  --input-csv "$malformed_csv" \
  --inventory-json "$inventory" \
  --resource-group internship_proxym \
  --output-csv "${test_directory}/malformed-output.csv" \
  --metadata-json "${test_directory}/malformed-metadata.json" \
  --timestamp 2026-08-31T00:00:00Z \
  --subscription-id "$SUBSCRIPTION_ID" >/dev/null 2>&1; then
  fail "malformed CSV was accepted"
fi
pass "malformed CSV fails"

empty_csv="${test_directory}/empty-result.csv"
printf '%s\n' \
  'CHECK_ID;PROVIDER;STATUS;SEVERITY;RESOURCE_UID' \
  'other;azure;FAIL;high;/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/elsewhere/providers/Microsoft.Network/virtualNetworks/main' \
  >"$empty_csv"
if python3 "$FILTER_SCRIPT" \
  --input-csv "$empty_csv" \
  --inventory-json "$inventory" \
  --resource-group internship_proxym \
  --output-csv "${test_directory}/empty-output.csv" \
  --metadata-json "${test_directory}/empty-metadata.json" \
  --timestamp 2026-08-31T00:00:00Z \
  --subscription-id "$SUBSCRIPTION_ID" >/dev/null 2>&1; then
  fail "unexpected empty result was accepted"
fi
pass "non-empty inventory with an empty scoped result fails"

run_orchestrator() {
  local case_name="$1"
  local az_mode="$2"
  local prowler_mode="$3"
  local curl_marker="$4"
  local prowler_marker="$5"
  local report_root="$6"
  local log_file="$7"
  local command_status=0
  local dd_token_value="${RUN_DD_TOKEN-$TEST_TOKEN}"
  local dd_test_id_value="${RUN_DD_TEST_ID-$TEST_DD_TEST_ID}"
  local dd_ca_cert_value="${RUN_DD_CA_CERT-}"
  local python_mode="${RUN_PYTHON_MODE:-success}"
  shift 7

  mkdir -p "$(dirname "$log_file")"
  env \
    AZ_BIN="${mock_bin}/az" \
    PROWLER_BIN="${mock_bin}/prowler" \
    CURL_BIN="${mock_bin}/curl" \
    PYTHON_BIN="${mock_bin}/python" \
    REAL_PYTHON_BIN="$(command -v python3)" \
    TEE_BIN="$(command -v tee)" \
    PROWLER_REPORT_ROOT="$report_root" \
    DD_URL="https://dojo.invalid" \
    DD_TOKEN="$dd_token_value" \
    DD_TEST_ID="$dd_test_id_value" \
    DD_CA_CERT="$dd_ca_cert_value" \
    MOCK_AZ_MODE="$az_mode" \
    MOCK_PROWLER_MODE="$prowler_mode" \
    MOCK_PYTHON_MODE="$python_mode" \
    MOCK_CURL_MARKER="$curl_marker" \
    MOCK_PROWLER_MARKER="$prowler_marker" \
    "$ORCHESTRATOR" "$@" >"$log_file" 2>&1 || command_status=$?
  : "$case_name"
  return "$command_status"
}

success_directory="${test_directory}/success"
if ! run_orchestrator success success success \
  "${success_directory}/curl-called" "${success_directory}/prowler-called" \
  "${success_directory}/reports" "${success_directory}/run.log"; then
  fail "successful mocked reimport flow"
fi
[[ -e "${success_directory}/curl-called" ]] || fail "DefectDojo was not called after valid filtering"
grep -q 'close_old_findings=false' "${success_directory}/run.log" || \
  fail "safe close_old_findings setting was not reported"
pass "valid scan is filtered and reimported with close_old_findings=false"

dry_directory="${test_directory}/dry-run"
if ! run_orchestrator dry-run success success \
  "${dry_directory}/curl-called" "${dry_directory}/prowler-called" \
  "${dry_directory}/reports" "${dry_directory}/run.log" --no-defectdojo; then
  fail "manual dry-run mode"
fi
[[ -e "${dry_directory}/prowler-called" ]] || fail "dry-run did not scan"
assert_not_called "${dry_directory}/curl-called" "dry-run called DefectDojo"
find "${dry_directory}/reports" -name 'prowler-internship-proxym.csv' -type f | grep -q . || \
  fail "dry-run did not create filtered report"
pass "--no-defectdojo scans and filters without upload"

scan_failure_directory="${test_directory}/scan-failure"
if run_orchestrator scan-failure success scan_fail \
  "${scan_failure_directory}/curl-called" "${scan_failure_directory}/prowler-called" \
  "${scan_failure_directory}/reports" "${scan_failure_directory}/run.log"; then
  fail "Prowler failure was accepted"
fi
assert_not_called "${scan_failure_directory}/curl-called" "DefectDojo called after Prowler failure"
pass "DefectDojo is not called after Prowler failure"

malformed_directory="${test_directory}/orchestrator-malformed"
if run_orchestrator malformed success malformed \
  "${malformed_directory}/curl-called" "${malformed_directory}/prowler-called" \
  "${malformed_directory}/reports" "${malformed_directory}/run.log"; then
  fail "orchestrator accepted malformed CSV"
fi
assert_not_called "${malformed_directory}/curl-called" "DefectDojo called after malformed CSV"
pass "DefectDojo is not called after malformed CSV filtering failure"

empty_directory="${test_directory}/orchestrator-empty"
if run_orchestrator empty-filter success empty_filter \
  "${empty_directory}/curl-called" "${empty_directory}/prowler-called" \
  "${empty_directory}/reports" "${empty_directory}/run.log"; then
  fail "orchestrator accepted unexpectedly empty result"
fi
assert_not_called "${empty_directory}/curl-called" "DefectDojo called after empty filtered result"
pass "DefectDojo is not called after unexpected empty filtering result"

missing_directory="${test_directory}/missing-csv"
if run_orchestrator missing-csv success missing_csv \
  "${missing_directory}/curl-called" "${missing_directory}/prowler-called" \
  "${missing_directory}/reports" "${missing_directory}/run.log"; then
  fail "orchestrator accepted missing CSV"
fi
assert_not_called "${missing_directory}/curl-called" "DefectDojo called after missing CSV"
pass "DefectDojo is not called when the Prowler CSV is missing"

inventory_directory="${test_directory}/inventory-failure"
if run_orchestrator inventory-failure inventory_fail success \
  "${inventory_directory}/curl-called" "${inventory_directory}/prowler-called" \
  "${inventory_directory}/reports" "${inventory_directory}/run.log"; then
  fail "orchestrator accepted Azure inventory failure"
fi
assert_not_called "${inventory_directory}/prowler-called" "Prowler called after inventory failure"
assert_not_called "${inventory_directory}/curl-called" "DefectDojo called after inventory failure"
pass "inventory failure prevents both Prowler and DefectDojo calls"

metadata_directory="${test_directory}/metadata-failure"
if RUN_PYTHON_MODE=metadata_fail run_orchestrator metadata-failure success success \
  "${metadata_directory}/curl-called" "${metadata_directory}/prowler-called" \
  "${metadata_directory}/reports" "${metadata_directory}/run.log"; then
  fail "orchestrator accepted metadata generation failure"
fi
assert_not_called "${metadata_directory}/curl-called" "DefectDojo called after metadata failure"
find "${metadata_directory}/reports" -name 'prowler-internship-proxym.csv' -type f | grep -q . || \
  fail "filtered report was not retained after metadata failure"
pass "metadata failure prevents DefectDojo and retains the local filtered report"

missing_token_directory="${test_directory}/missing-token"
if RUN_DD_TOKEN='' run_orchestrator missing-token success success \
  "${missing_token_directory}/curl-called" "${missing_token_directory}/prowler-called" \
  "${missing_token_directory}/reports" "${missing_token_directory}/run.log"; then
  fail "orchestrator accepted missing DD_TOKEN"
fi
assert_not_called "${missing_token_directory}/curl-called" "DefectDojo called without DD_TOKEN"
find "${missing_token_directory}/reports" -name 'prowler-internship-proxym.csv' -type f | grep -q . || \
  fail "local report was not retained when DD_TOKEN was missing"
pass "missing DD_TOKEN prevents upload and retains local reports"

missing_test_directory="${test_directory}/missing-test-id"
if RUN_DD_TEST_ID='' run_orchestrator missing-test-id success success \
  "${missing_test_directory}/curl-called" "${missing_test_directory}/prowler-called" \
  "${missing_test_directory}/reports" "${missing_test_directory}/run.log"; then
  fail "orchestrator accepted missing DD_TEST_ID"
fi
assert_not_called "${missing_test_directory}/curl-called" "DefectDojo called without DD_TEST_ID"
find "${missing_test_directory}/reports" -name 'prowler-internship-proxym.csv' -type f | grep -q . || \
  fail "local report was not retained when DD_TEST_ID was missing"
pass "missing DD_TEST_ID prevents upload and retains local reports"

tls_directory="${test_directory}/tls-failure"
if RUN_DD_CA_CERT="${tls_directory}/missing-ca.crt" run_orchestrator tls-failure success success \
  "${tls_directory}/curl-called" "${tls_directory}/prowler-called" \
  "${tls_directory}/reports" "${tls_directory}/run.log"; then
  fail "orchestrator accepted unreadable DD_CA_CERT"
fi
assert_not_called "${tls_directory}/curl-called" "DefectDojo called with unreadable DD_CA_CERT"
pass "TLS CA validation failure prevents DefectDojo upload"

overlap_directory="${test_directory}/overlap"
mkdir -p "${overlap_directory}/reports"
exec 8>"${overlap_directory}/reports/.scheduled-rg-scan.lock"
flock --nonblock 8 || fail "could not establish overlap test lock"
if run_orchestrator overlap success success \
  "${overlap_directory}/curl-called" "${overlap_directory}/prowler-called" \
  "${overlap_directory}/reports" "${overlap_directory}/run.log"; then
  fail "orchestrator allowed an overlapping execution"
fi
flock --unlock 8
exec 8>&-
assert_not_called "${overlap_directory}/prowler-called" "Prowler called during overlapping execution"
assert_not_called "${overlap_directory}/curl-called" "DefectDojo called during overlapping execution"
pass "overlapping executions are rejected before Azure/Prowler/DefectDojo work"

if grep -R --fixed-strings "$TEST_TOKEN" "$test_directory" >/dev/null 2>&1; then
  fail "DD_TOKEN value appeared in test logs or generated reports"
fi
pass "DD_TOKEN value never appears in logs or generated reports"

printf 'All %s tests passed.\n' "$tests_run"
