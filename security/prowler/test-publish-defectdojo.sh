#!/usr/bin/env bash

set -euo pipefail

readonly SCRIPT_DIRECTORY="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly REPOSITORY_ROOT="$(cd "${SCRIPT_DIRECTORY}/../.." && pwd)"
readonly PUBLISHER="${SCRIPT_DIRECTORY}/publish-defectdojo.sh"
readonly MOCK_DISPATCHER="${SCRIPT_DIRECTORY}/tests/mock-command.sh"
readonly CIRCLECI_CONFIG="${REPOSITORY_ROOT}/.circleci/config.yml"
readonly WORKSPACE_PREPARER="${REPOSITORY_ROOT}/.circleci/scripts/prepare-circleci-workspace.sh"
readonly TEST_TOKEN="publisher-test-token-that-must-not-be-logged"

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

mock_bin="${test_directory}/bin"
mkdir -p "$mock_bin"
ln -s "$MOCK_DISPATCHER" "${mock_bin}/curl"
ca_certificate="${test_directory}/test-ca.pem"
printf '%s\n' 'mock test CA' >"$ca_certificate"

create_bundle() {
  local directory="$1"
  local mode="$2"
  mkdir -p "$directory"
  python3 - "$directory" "$mode" <<'PY'
import csv
import hashlib
import json
import sys
from pathlib import Path

directory = Path(sys.argv[1])
mode = sys.argv[2]
csv_path = directory / "prowler-internship-proxym.csv"
metadata_path = directory / "metadata.json"
manifest_path = directory / "manifest.json"
subscription_id = "00000000-0000-0000-0000-000000000001"
resource_group = "another_group" if mode == "wrong_rg" else "internship_proxym"

if mode == "malformed":
    csv_path.write_text("CHECK_ID;STATUS;SEVERITY\nbad;FAIL;HIGH\n", encoding="utf-8")
    total, passed, failed, high = 1, 0, 1, 1
elif mode == "empty":
    csv_path.write_text(
        "CHECK_ID;PROVIDER;STATUS;SEVERITY;RESOURCE_UID\n", encoding="utf-8"
    )
    total = passed = failed = high = 0
else:
    uid_resource_group = "another_group" if mode == "out_of_scope_uid" else resource_group
    uid = (
        f"/subscriptions/{subscription_id}/resourceGroups/{uid_resource_group}/"
        "providers/Microsoft.Network/virtualNetworks/main"
    )
    with csv_path.open("w", encoding="utf-8", newline="") as csv_file:
        writer = csv.writer(csv_file, delimiter=";", lineterminator="\n")
        writer.writerow(["CHECK_ID", "PROVIDER", "STATUS", "SEVERITY", "RESOURCE_UID"])
        writer.writerow(["passing-check", "azure", "PASS", "LOW", uid])
        writer.writerow(["failing-check", "azure", "FAIL", "HIGH", uid])
    total, passed, failed, high = 2, 1, 1, 1

metadata = {
    "timestamp": "2026-08-31T19:59:18Z",
    "subscription_id": subscription_id,
    "resource_group": resource_group,
    "azure_resource_count": 1,
    "full_prowler_finding_count": total,
    "filtered_rg_finding_count": total,
    "severity_counts": {"critical": 0, "high": high, "medium": 0, "low": 0},
    "filtered_status_counts": {"pass": passed, "fail": failed},
    "scan_success_status": "SUCCESS",
}
metadata_path.write_text(json.dumps(metadata, indent=2, sort_keys=True) + "\n", encoding="utf-8")

def sha256(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

manifest = {
    "subscription_id": subscription_id,
    "resource_group": resource_group,
    "scan_timestamp": metadata["timestamp"],
    "finding_counts": {
        "total": total,
        "pass": passed,
        "fail": failed,
        "critical": 0,
        "high": high,
        "medium": 0,
        "low": 0,
    },
    "sha256": {
        "prowler-internship-proxym.csv": sha256(csv_path),
        "metadata.json": sha256(metadata_path),
    },
}
manifest_path.write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n", encoding="utf-8")
PY
}

run_publisher() {
  local bundle_directory="$1"
  local marker="$2"
  local log_file="$3"
  local token="${RUN_DD_TOKEN-$TEST_TOKEN}"
  local test_id="${RUN_DD_TEST_ID-1429}"
  local ca_cert="${RUN_DD_CA_CERT-$ca_certificate}"

  env \
    PYTHON_BIN="$(command -v python3)" \
    CURL_BIN="${mock_bin}/curl" \
    DD_URL="https://dojo.invalid" \
    DD_TOKEN="$token" \
    DD_TEST_ID="$test_id" \
    DD_CA_CERT="$ca_cert" \
    MOCK_CURL_MARKER="$marker" \
    bash "$PUBLISHER" \
      --csv "${bundle_directory}/prowler-internship-proxym.csv" \
      --metadata "${bundle_directory}/metadata.json" \
      --manifest "${bundle_directory}/manifest.json" >"$log_file" 2>&1
}

workspace_test_repository="${test_directory}/workspace-repository"
workspace_root="${workspace_test_repository}/.circleci-workspace"
unrelated_sentinel="${workspace_test_repository}/unrelated-file-must-survive.txt"
external_directory="${test_directory}/outside-repository"
mkdir -p "$workspace_test_repository" "$external_directory"
git -C "$workspace_test_repository" init -q
printf '%s\n' 'must survive workspace cleanup' >"$unrelated_sentinel"
printf '%s\n' 'must survive symlink rejection' >"${external_directory}/external-sentinel.txt"

run_workspace_preparer() {
  (cd "$workspace_test_repository" && bash "$WORKSPACE_PREPARER")
}

run_workspace_preparer >/dev/null || fail "first local workspace preparation"
[[ -d "$workspace_root" ]] || fail "first preparation did not create the workspace root"
[[ -z "$(find "$workspace_root" -mindepth 1 -print -quit)" ]] || \
  fail "first preparation did not create an empty workspace root"
pass "first local workspace preparation succeeds without existing state"

stale_bundle="${workspace_root}/prowler"
mkdir -p "$stale_bundle"
for stale_file in manifest.json metadata.json prowler-internship-proxym.csv; do
  printf 'stale previous run: %s\n' "$stale_file" >"${stale_bundle}/${stale_file}"
done
printf '%s\n' 'unexpected stale file' >"${stale_bundle}/stale-only.txt"
run_workspace_preparer >/dev/null || fail "stale local workspace cleanup"
[[ -d "$workspace_root" ]] || fail "stale cleanup did not recreate the workspace root"
[[ -z "$(find "$workspace_root" -mindepth 1 -print -quit)" ]] || \
  fail "stale files survived local workspace cleanup"
pass "second local workspace preparation removes every stale bundle file"

[[ -f "$unrelated_sentinel" ]] || fail "workspace cleanup removed an unrelated repository file"
grep -Fqx 'must survive workspace cleanup' "$unrelated_sentinel" || \
  fail "workspace cleanup changed an unrelated repository file"
pass "workspace cleanup preserves unrelated repository files"

create_bundle "${workspace_root}/prowler" valid
actual_bundle_files="$(
  find "${workspace_root}/prowler" -mindepth 1 -maxdepth 1 -type f -printf '%f\n' | sort
)"
expected_bundle_files=$'manifest.json\nmetadata.json\nprowler-internship-proxym.csv'
[[ "$actual_bundle_files" == "$expected_bundle_files" ]] || \
  fail "prepared workspace bundle does not contain exactly the expected files"
if grep -R --fixed-strings 'stale previous run:' "${workspace_root}/prowler" >/dev/null 2>&1; then
  fail "stale bundle contents survived into the replacement bundle"
fi
pass "replacement workspace bundle contains exactly the three validated files"

run_workspace_preparer >/dev/null || fail "first repeated publisher attachment preparation"
run_workspace_preparer >/dev/null || fail "second repeated publisher attachment preparation"
[[ -d "$workspace_root" && -z "$(find "$workspace_root" -mindepth 1 -print -quit)" ]] || \
  fail "repeated publisher attachment preparation did not leave an empty target"
pass "publisher workspace attachment target can be prepared repeatedly"

rmdir "$workspace_root"
ln -s "$external_directory" "$workspace_root"
if run_workspace_preparer >/dev/null 2>&1; then
  fail "symlinked CircleCI workspace root was accepted"
fi
[[ -L "$workspace_root" ]] || fail "symlink rejection removed the workspace link"
[[ -f "${external_directory}/external-sentinel.txt" ]] || \
  fail "symlink rejection modified data outside the repository"
rm -- "$workspace_root"
pass "symlinked workspace root is rejected without escaping the repository"

printf '%s\n' 'not a directory' >"$workspace_root"
if run_workspace_preparer >/dev/null 2>&1; then
  fail "regular-file CircleCI workspace root was accepted"
fi
grep -Fqx 'not a directory' "$workspace_root" || \
  fail "regular-file workspace rejection changed the file"
rm -- "$workspace_root"
pass "regular-file workspace root is rejected without modification"

mkdir -p "${workspace_test_repository}/nested"
if (cd "${workspace_test_repository}/nested" && \
  bash "$WORKSPACE_PREPARER" >/dev/null 2>&1); then
  fail "workspace cleanup ran outside the repository root"
fi
if (cd "$workspace_test_repository" && \
  bash "$WORKSPACE_PREPARER" "$external_directory" >/dev/null 2>&1); then
  fail "workspace cleanup accepted an alternate target"
fi
[[ -f "$unrelated_sentinel" && -f "${external_directory}/external-sentinel.txt" ]] || \
  fail "out-of-root cleanup attempt modified unrelated data"
pass "workspace cleanup cannot run outside the repository root or accept another target"

valid_bundle="${test_directory}/valid"
create_bundle "$valid_bundle" valid
valid_marker="${valid_bundle}/curl-called"
valid_log="${valid_bundle}/publish.log"
run_publisher "$valid_bundle" "$valid_marker" "$valid_log" || fail "valid publication bundle"
[[ -e "$valid_marker" ]] || fail "valid bundle was not published"
grep -q 'close_old_findings=false' "$valid_log" || fail "safe close setting was not reported"
pass "valid workspace bundle is published with close_old_findings=false"

missing_bundle="${test_directory}/missing"
create_bundle "$missing_bundle" valid
missing_marker="${missing_bundle}/curl-called"
if env PYTHON_BIN="$(command -v python3)" CURL_BIN="${mock_bin}/curl" \
  DD_URL=https://dojo.invalid DD_TOKEN="$TEST_TOKEN" DD_TEST_ID=1429 \
  DD_CA_CERT="$ca_certificate" MOCK_CURL_MARKER="$missing_marker" \
  bash "$PUBLISHER" \
    --csv "${missing_bundle}/does-not-exist.csv" \
    --metadata "${missing_bundle}/metadata.json" \
    --manifest "${missing_bundle}/manifest.json" >/dev/null 2>&1; then
  fail "missing CSV was accepted"
fi
[[ ! -e "$missing_marker" ]] || fail "DefectDojo was called for a missing CSV"
pass "missing CSV is rejected before DefectDojo"

malformed_bundle="${test_directory}/malformed"
create_bundle "$malformed_bundle" malformed
malformed_marker="${malformed_bundle}/curl-called"
if run_publisher "$malformed_bundle" "$malformed_marker" \
  "${malformed_bundle}/publish.log"; then
  fail "malformed CSV was accepted"
fi
[[ ! -e "$malformed_marker" ]] || fail "DefectDojo was called for malformed CSV"
pass "malformed CSV is rejected before DefectDojo"

empty_bundle="${test_directory}/empty"
create_bundle "$empty_bundle" empty
empty_marker="${empty_bundle}/curl-called"
if run_publisher "$empty_bundle" "$empty_marker" "${empty_bundle}/publish.log"; then
  fail "empty CSV was accepted"
fi
[[ ! -e "$empty_marker" ]] || fail "DefectDojo was called for empty CSV"
pass "empty CSV is rejected before DefectDojo"

wrong_rg_bundle="${test_directory}/wrong-rg"
create_bundle "$wrong_rg_bundle" wrong_rg
wrong_rg_marker="${wrong_rg_bundle}/curl-called"
if run_publisher "$wrong_rg_bundle" "$wrong_rg_marker" \
  "${wrong_rg_bundle}/publish.log"; then
  fail "wrong resource group was accepted"
fi
[[ ! -e "$wrong_rg_marker" ]] || fail "DefectDojo was called for the wrong resource group"
pass "wrong resource group is rejected before DefectDojo"

out_of_scope_bundle="${test_directory}/out-of-scope"
create_bundle "$out_of_scope_bundle" out_of_scope_uid
out_of_scope_marker="${out_of_scope_bundle}/curl-called"
if run_publisher "$out_of_scope_bundle" "$out_of_scope_marker" \
  "${out_of_scope_bundle}/publish.log"; then
  fail "out-of-scope RESOURCE_UID was accepted"
fi
[[ ! -e "$out_of_scope_marker" ]] || fail "DefectDojo was called for an out-of-scope UID"
pass "every CSV RESOURCE_UID must belong to internship_proxym"

checksum_bundle="${test_directory}/checksum"
create_bundle "$checksum_bundle" valid
printf '\n' >>"${checksum_bundle}/prowler-internship-proxym.csv"
checksum_marker="${checksum_bundle}/curl-called"
if run_publisher "$checksum_bundle" "$checksum_marker" \
  "${checksum_bundle}/publish.log"; then
  fail "checksum mismatch was accepted"
fi
[[ ! -e "$checksum_marker" ]] || fail "DefectDojo was called after checksum mismatch"
pass "checksum mismatch is rejected before DefectDojo"

missing_token_bundle="${test_directory}/missing-token"
create_bundle "$missing_token_bundle" valid
missing_token_marker="${missing_token_bundle}/curl-called"
if RUN_DD_TOKEN='' run_publisher "$missing_token_bundle" "$missing_token_marker" \
  "${missing_token_bundle}/publish.log"; then
  fail "missing DD_TOKEN was accepted"
fi
[[ ! -e "$missing_token_marker" ]] || fail "DefectDojo was called without DD_TOKEN"
pass "DD_TOKEN is required by the publication job"

missing_ca_bundle="${test_directory}/missing-ca"
create_bundle "$missing_ca_bundle" valid
missing_ca_marker="${missing_ca_bundle}/curl-called"
if RUN_DD_CA_CERT='' run_publisher "$missing_ca_bundle" "$missing_ca_marker" \
  "${missing_ca_bundle}/publish.log"; then
  fail "missing DD_CA_CERT was accepted"
fi
[[ ! -e "$missing_ca_marker" ]] || fail "DefectDojo was called without DD_CA_CERT"
pass "DD_CA_CERT is required by the publication job"

wrong_test_bundle="${test_directory}/wrong-test"
create_bundle "$wrong_test_bundle" valid
wrong_test_marker="${wrong_test_bundle}/curl-called"
if RUN_DD_TEST_ID=1428 run_publisher "$wrong_test_bundle" "$wrong_test_marker" \
  "${wrong_test_bundle}/publish.log"; then
  fail "DD_TEST_ID 1428 was accepted"
fi
[[ ! -e "$wrong_test_marker" ]] || fail "DefectDojo Test 1428 was called"
pass "DD_TEST_ID must be the dedicated Test 1429"

python3 - "$CIRCLECI_CONFIG" <<'PY' || fail "CircleCI Prowler workflow structure"
import json
import sys
import yaml

with open(sys.argv[1], encoding="utf-8") as config_file:
    config = yaml.safe_load(config_file)

scan = config["jobs"]["prowler-rg-security-scan"]
publish = config["jobs"]["publish-prowler-defectdojo"]
scan_text = json.dumps(scan)
publish_text = json.dumps(publish)
assert scan["machine"] is True
assert scan["resource_class"] == "drghassen/sonar-vm"
assert publish["machine"] is True
assert publish["resource_class"] == "drghassen/sonar-vm"
assert "--no-defectdojo" in scan_text
assert "DD_TOKEN" not in scan_text
assert "DD_TEST_ID" not in scan_text
assert "AZURE_CLIENT_ID" not in publish_text
assert "AZURE_TENANT_ID" not in publish_text
assert "AZURE_SUBSCRIPTION_ID" not in publish_text
assert "aca_authenticate_with_circleci_oidc" not in publish_text
assert "bash .circleci/scripts/prepare-circleci-workspace.sh" in scan_text

persist = next(step["persist_to_workspace"] for step in scan["steps"] if "persist_to_workspace" in step)
assert persist == {"root": ".circleci-workspace", "paths": ["prowler"]}

publish_steps = publish["steps"]
attach_index = next(index for index, step in enumerate(publish_steps) if "attach_workspace" in step)
assert publish_steps[attach_index - 1]["run"]["command"] == \
    "bash .circleci/scripts/prepare-circleci-workspace.sh"
assert publish_steps[attach_index]["attach_workspace"] == {"at": ".circleci-workspace"}

workflow_jobs = config["workflows"]["prowler-rg-security-scan"]["jobs"]
scan_invocation = workflow_jobs[0]["prowler-rg-security-scan"]
publish_invocation = workflow_jobs[1]["publish-prowler-defectdojo"]
assert scan_invocation["context"] == ["aca-deploy"]
assert publish_invocation["context"] == ["prowler-security"]
assert publish_invocation["requires"] == ["prowler-rg-security-scan"]
PY
pass "CircleCI jobs have isolated contexts, responsibilities, and dependency"

grep -q -- "--form 'close_old_findings=false'" "$PUBLISHER" || \
  fail "publisher does not enforce close_old_findings=false"
if grep -Eq -- '(^|[[:space:]])(-k|--insecure)([[:space:]]|$)' "$PUBLISHER"; then
  fail "publisher disables TLS verification"
fi
pass "publisher enforces safe finding closure and verified TLS"

if grep -R --fixed-strings "$TEST_TOKEN" "$test_directory" >/dev/null 2>&1; then
  fail "DD_TOKEN value appeared in publication logs or generated reports"
fi
pass "DD_TOKEN value never appears in publication logs or reports"

printf 'All %s publication tests passed.\n' "$tests_run"
