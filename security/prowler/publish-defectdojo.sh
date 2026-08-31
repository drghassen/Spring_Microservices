#!/usr/bin/env bash

set -euo pipefail
umask 077

readonly EXPECTED_RESOURCE_GROUP="internship_proxym"
readonly EXPECTED_DD_TEST_ID="1429"
readonly DD_SCAN_TYPE="Prowler Scan"

usage() {
  printf 'Usage: %s --csv PATH --metadata PATH --manifest PATH\n' "${0##*/}"
}

find_command() {
  local configured_command="$1"
  local description="$2"

  command -v "$configured_command" >/dev/null 2>&1 || {
    printf '%s is required.\n' "$description" >&2
    return 1
  }
  command -v "$configured_command"
}

csv_path=""
metadata_path=""
manifest_path=""
while (($#)); do
  case "$1" in
    --csv)
      [[ $# -ge 2 ]] || { usage >&2; exit 2; }
      csv_path="$2"
      shift 2
      ;;
    --metadata)
      [[ $# -ge 2 ]] || { usage >&2; exit 2; }
      metadata_path="$2"
      shift 2
      ;;
    --manifest)
      [[ $# -ge 2 ]] || { usage >&2; exit 2; }
      manifest_path="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      usage >&2
      exit 2
      ;;
  esac
done

for input_path in "$csv_path" "$metadata_path" "$manifest_path"; do
  [[ -n "$input_path" && -f "$input_path" && ! -L "$input_path" && -r "$input_path" ]] || {
    echo "The Prowler publication bundle is incomplete or unsafe." >&2
    exit 1
  }
done

python_bin="$(find_command "${PYTHON_BIN:-python3}" "Python 3")"
curl_bin="$(find_command "${CURL_BIN:-curl}" "curl")"

"$python_bin" - \
  "$csv_path" \
  "$metadata_path" \
  "$manifest_path" \
  "$EXPECTED_RESOURCE_GROUP" <<'PY'
import csv
import hashlib
import json
import re
import sys
import uuid
from collections import Counter
from pathlib import Path

csv_path, metadata_path, manifest_path = map(Path, sys.argv[1:4])
expected_resource_group = sys.argv[4]


def fail(message):
    raise SystemExit(f"Prowler publication validation failed: {message}")


def load_json(path, description):
    try:
        with path.open(encoding="utf-8") as source:
            value = json.load(source)
    except (OSError, UnicodeError, json.JSONDecodeError) as error:
        fail(f"{description} is unreadable or malformed: {error}")
    if not isinstance(value, dict):
        fail(f"{description} must be a JSON object")
    return value


def require_non_negative_integer(value, description):
    if isinstance(value, bool) or not isinstance(value, int) or value < 0:
        fail(f"{description} must be a non-negative integer")
    return value


def sha256(path):
    digest = hashlib.sha256()
    try:
        with path.open("rb") as source:
            for chunk in iter(lambda: source.read(1024 * 1024), b""):
                digest.update(chunk)
    except OSError as error:
        fail(f"cannot hash {path.name}: {error}")
    return digest.hexdigest()


manifest = load_json(manifest_path, "manifest.json")
if set(manifest) != {
    "subscription_id",
    "resource_group",
    "scan_timestamp",
    "finding_counts",
    "sha256",
}:
    fail("manifest.json has unexpected or missing fields")

manifest_hashes = manifest["sha256"]
if not isinstance(manifest_hashes, dict) or set(manifest_hashes) != {
    "prowler-internship-proxym.csv",
    "metadata.json",
}:
    fail("manifest.json has invalid SHA256 fields")
for filename, expected_digest, path in (
    ("prowler-internship-proxym.csv", manifest_hashes.get("prowler-internship-proxym.csv"), csv_path),
    ("metadata.json", manifest_hashes.get("metadata.json"), metadata_path),
):
    if not isinstance(expected_digest, str) or not re.fullmatch(r"[0-9a-f]{64}", expected_digest):
        fail(f"manifest SHA256 for {filename} is invalid")
    if sha256(path) != expected_digest:
        fail(f"SHA256 mismatch for {filename}")

metadata = load_json(metadata_path, "metadata.json")
subscription_id = metadata.get("subscription_id")
try:
    if not isinstance(subscription_id, str):
        raise ValueError
    uuid.UUID(subscription_id)
except (ValueError, AttributeError):
    fail("metadata subscription_id is invalid")

if metadata.get("resource_group") != expected_resource_group:
    fail("metadata resource_group is not internship_proxym")
if manifest.get("resource_group") != expected_resource_group:
    fail("manifest resource_group is not internship_proxym")
if manifest.get("subscription_id") != subscription_id:
    fail("manifest and metadata subscription IDs differ")
if manifest.get("scan_timestamp") != metadata.get("timestamp") or not isinstance(
    metadata.get("timestamp"), str
):
    fail("manifest and metadata scan timestamps differ")
if metadata.get("scan_success_status") != "SUCCESS":
    fail("metadata does not record a successful scan")

filtered_count = require_non_negative_integer(
    metadata.get("filtered_rg_finding_count"), "filtered finding count"
)
if filtered_count == 0:
    fail("filtered Prowler CSV is unexpectedly empty")
full_count = require_non_negative_integer(
    metadata.get("full_prowler_finding_count"), "full finding count"
)
if full_count < filtered_count:
    fail("full finding count is smaller than filtered finding count")

status_metadata = metadata.get("filtered_status_counts")
severity_metadata = metadata.get("severity_counts")
if not isinstance(status_metadata, dict) or set(status_metadata) != {"pass", "fail"}:
    fail("metadata status counts are invalid")
if not isinstance(severity_metadata, dict) or set(severity_metadata) != {
    "critical",
    "high",
    "medium",
    "low",
}:
    fail("metadata severity counts are invalid")
expected_status = {
    key: require_non_negative_integer(value, f"{key} status count")
    for key, value in status_metadata.items()
}
expected_severity = {
    key: require_non_negative_integer(value, f"{key} severity count")
    for key, value in severity_metadata.items()
}
if sum(expected_status.values()) != filtered_count:
    fail("metadata status counts do not equal the filtered finding count")
if sum(expected_severity.values()) != expected_status["fail"]:
    fail("metadata severity counts do not equal the FAIL count")

required_columns = {"CHECK_ID", "PROVIDER", "RESOURCE_UID", "SEVERITY", "STATUS"}
status_counts = Counter()
severity_counts = Counter()
row_count = 0
resource_prefix = (
    f"/subscriptions/{subscription_id}/resourcegroups/{expected_resource_group}/".casefold()
)
try:
    with csv_path.open(encoding="utf-8-sig", newline="") as csv_file:
        reader = csv.DictReader(csv_file, delimiter=";", strict=True)
        fieldnames = reader.fieldnames
        if not fieldnames or any(not field for field in fieldnames):
            fail("CSV has no valid header")
        if len(fieldnames) != len(set(fieldnames)):
            fail("CSV has duplicate columns")
        if not required_columns.issubset(fieldnames):
            fail("CSV is missing required Prowler columns")
        for line_number, row in enumerate(reader, start=2):
            if None in row or any(value is None for value in row.values()):
                fail(f"CSV row {line_number} has the wrong column count")
            if not row["CHECK_ID"].strip() or not row["PROVIDER"].strip():
                fail(f"CSV row {line_number} lacks finding identity fields")
            resource_uid = row["RESOURCE_UID"].strip().rstrip("/").casefold()
            if not resource_uid.startswith(resource_prefix):
                fail(f"CSV row {line_number} is outside internship_proxym")
            status = row["STATUS"].strip().upper()
            severity = row["SEVERITY"].strip().upper()
            if status not in {"PASS", "FAIL"} or not severity:
                fail(f"CSV row {line_number} has an invalid status or severity")
            status_counts[status] += 1
            if status == "FAIL":
                if severity not in {"CRITICAL", "HIGH", "MEDIUM", "LOW"}:
                    fail(f"CSV row {line_number} has an unsupported FAIL severity")
                severity_counts[severity] += 1
            row_count += 1
except (OSError, UnicodeError, csv.Error) as error:
    fail(f"CSV is unreadable or malformed: {error}")

if row_count == 0 or row_count != filtered_count:
    fail("CSV row count does not match metadata")
actual_status = {"pass": status_counts["PASS"], "fail": status_counts["FAIL"]}
actual_severity = {
    "critical": severity_counts["CRITICAL"],
    "high": severity_counts["HIGH"],
    "medium": severity_counts["MEDIUM"],
    "low": severity_counts["LOW"],
}
if actual_status != expected_status or actual_severity != expected_severity:
    fail("CSV counts do not match metadata")

expected_manifest_counts = {
    "total": filtered_count,
    "pass": expected_status["pass"],
    "fail": expected_status["fail"],
    **expected_severity,
}
if manifest.get("finding_counts") != expected_manifest_counts:
    fail("manifest finding counts do not match metadata")

print(
    "Validated Prowler bundle: "
    f"total={filtered_count} pass={expected_status['pass']} fail={expected_status['fail']}"
)
PY

[[ -n "${DD_TOKEN:-}" ]] || {
  echo "DD_TOKEN is required for DefectDojo publication." >&2
  exit 1
}
[[ "$DD_TOKEN" =~ ^[A-Za-z0-9._~-]+$ ]] || {
  echo "DD_TOKEN contains characters unsafe for curl's in-memory config." >&2
  exit 1
}
[[ "${DD_TEST_ID:-}" == "$EXPECTED_DD_TEST_ID" ]] || {
  echo "DD_TEST_ID must target the dedicated resource-group Test 1429." >&2
  exit 1
}
[[ -n "${DD_URL:-}" && "$DD_URL" == https://* && "$DD_URL" != *[[:space:]]* ]] || {
  echo "DD_URL must be a non-empty HTTPS URL." >&2
  exit 1
}
[[ -n "${DD_CA_CERT:-}" && -f "$DD_CA_CERT" && -r "$DD_CA_CERT" ]] || {
  echo "DD_CA_CERT must identify a readable CA certificate." >&2
  exit 1
}

dd_endpoint="${DD_URL%/}/api/v2/reimport-scan/"
printf 'Publishing validated Prowler report to DefectDojo test=%s.\n' "$DD_TEST_ID"
http_status="$({ printf 'header = "Authorization: Token %s"\n' "$DD_TOKEN"; } | \
  "$curl_bin" --config - \
    --fail-with-body \
    --silent \
    --show-error \
    --request POST \
    --cacert "$DD_CA_CERT" \
    --form "scan_type=${DD_SCAN_TYPE}" \
    --form "test=${DD_TEST_ID}" \
    --form 'minimum_severity=Info' \
    --form 'active=true' \
    --form 'verified=true' \
    --form 'close_old_findings=false' \
    --form "file=@${csv_path};type=text/csv" \
    --output /dev/null \
    --write-out '%{http_code}' \
    "$dd_endpoint")"
printf 'DefectDojo publication status: COMPLETED (HTTP %s, close_old_findings=false)\n' \
  "$http_status"
