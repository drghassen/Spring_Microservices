#!/usr/bin/env bash

set -euo pipefail
umask 077

readonly SCRIPT_DIRECTORY="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly REPOSITORY_ROOT="$(cd "${SCRIPT_DIRECTORY}/../.." && pwd)"
readonly RESOURCE_GROUP="internship_proxym"
readonly DD_SCAN_TYPE="Prowler Scan"
readonly DEFAULT_DD_URL="https://192.168.100.1:8443"

usage() {
  printf 'Usage: %s [--no-defectdojo]\n' "${0##*/}"
}

find_command() {
  local configured_command="$1"
  local description="$2"
  local fallback="${3:-}"

  if command -v "$configured_command" >/dev/null 2>&1; then
    command -v "$configured_command"
    return
  fi
  if [[ -n "$fallback" && -x "$fallback" ]]; then
    printf '%s\n' "$fallback"
    return
  fi

  printf '%s is required.\n' "$description" >&2
  return 1
}

upload_to_defectdojo=true
case "${1:-}" in
  "") ;;
  --no-defectdojo) upload_to_defectdojo=false ;;
  -h|--help)
    usage
    exit 0
    ;;
  *)
    usage >&2
    exit 2
    ;;
esac
if (($# > 1)); then
  usage >&2
  exit 2
fi

az_bin="$(find_command "${AZ_BIN:-az}" "Azure CLI")"
python_bin="$(find_command "${PYTHON_BIN:-python3}" "Python 3")"
prowler_bin="$(find_command "${PROWLER_BIN:-prowler}" "Prowler" "${HOME:-}/.local/bin/prowler")"
tee_bin="$(find_command "${TEE_BIN:-tee}" "tee")"
flock_bin="$(find_command "${FLOCK_BIN:-flock}" "flock")"
if [[ "$upload_to_defectdojo" == true ]]; then
  curl_bin="$(find_command "${CURL_BIN:-curl}" "curl")"
fi

report_root="${PROWLER_REPORT_ROOT:-${REPOSITORY_ROOT}/reports/prowler}"
mkdir -p "$report_root"
lock_file="${PROWLER_LOCK_FILE:-${report_root}/.scheduled-rg-scan.lock}"
exec 9>"$lock_file"
if ! "$flock_bin" --nonblock 9; then
  echo "Another scheduled Prowler resource-group scan is already running." >&2
  exit 75
fi

subscription_name="$("$az_bin" account show --query name --output tsv --only-show-errors)"
subscription_id="$("$az_bin" account show --query id --output tsv --only-show-errors)"
if [[ -z "$subscription_name" || -z "$subscription_id" ]]; then
  echo "Azure CLI did not return an active subscription." >&2
  exit 1
fi

timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
scan_started_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
scan_started_epoch="$(date +%s)"
scan_directory="${report_root}/${timestamp}"
full_directory="${scan_directory}/full"
rg_directory="${scan_directory}/${RESOURCE_GROUP}"
inventory_file="${full_directory}/azure-resource-inventory.json"
filtered_csv="${rg_directory}/prowler-internship-proxym.csv"
metadata_file="${rg_directory}/metadata.json"
mkdir -p "$full_directory" "$rg_directory"

printf 'Prowler version: %s\n' "$("$prowler_bin" --version)"
printf 'Azure subscription name: %s\n' "$subscription_name"
printf 'Azure subscription ID: %s\n' "$subscription_id"
printf 'Resource group: %s\n' "$RESOURCE_GROUP"
printf 'Scan start time (UTC): %s\n' "$scan_started_at"
printf 'Report directory: %s\n' "$scan_directory"

echo "Creating authoritative Azure resource-group inventory."
if ! "$az_bin" resource list \
  --resource-group "$RESOURCE_GROUP" \
  --subscription "$subscription_id" \
  --output json \
  --only-show-errors >"$inventory_file"; then
  echo "Azure resource-group inventory failed; Prowler and DefectDojo were not called." >&2
  exit 1
fi
if [[ ! -s "$inventory_file" ]]; then
  echo "Azure resource-group inventory is empty or missing." >&2
  exit 1
fi

echo "Starting normal read-only Prowler Azure subscription assessment."
set +e
"$prowler_bin" azure \
  --az-cli-auth \
  --subscription-id "$subscription_id" \
  --output-formats html csv json-ocsf \
  --output-directory "$full_directory" \
  --ignore-exit-code-3 \
  --no-color 2>&1 | "$tee_bin" "${full_directory}/prowler-console.log"
pipeline_status=("${PIPESTATUS[@]}")
set -e
if ((pipeline_status[0] != 0)); then
  printf 'Prowler exited abnormally with code %s; DefectDojo was not called.\n' \
    "${pipeline_status[0]}" >&2
  exit "${pipeline_status[0]}"
fi
if ((pipeline_status[1] != 0)); then
  echo "Could not retain the Prowler console log; DefectDojo was not called." >&2
  exit "${pipeline_status[1]}"
fi

mapfile -d '' full_csv_files < <(
  find "$full_directory" -maxdepth 1 -type f -name '*.csv' -print0
)
if ((${#full_csv_files[@]} != 1)); then
  printf 'Expected exactly one Prowler CSV in %s, found %s; DefectDojo was not called.\n' \
    "$full_directory" "${#full_csv_files[@]}" >&2
  exit 1
fi
full_csv="${full_csv_files[0]}"
if [[ ! -s "$full_csv" ]]; then
  echo "Prowler CSV is empty; DefectDojo was not called." >&2
  exit 1
fi

echo "Validating and filtering the Prowler CSV against the Azure inventory."
"$python_bin" "${SCRIPT_DIRECTORY}/filter-azure-rg-findings.py" \
  --input-csv "$full_csv" \
  --inventory-json "$inventory_file" \
  --resource-group "$RESOURCE_GROUP" \
  --output-csv "$filtered_csv" \
  --metadata-json "$metadata_file" \
  --timestamp "$scan_started_at" \
  --subscription-id "$subscription_id"

if [[ ! -s "$filtered_csv" || ! -s "$metadata_file" ]]; then
  echo "Filtered report validation failed; DefectDojo was not called." >&2
  exit 1
fi

"$python_bin" - "$metadata_file" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as metadata_file:
    metadata = json.load(metadata_file)
print(f"Azure resources inventoried: {metadata['azure_resource_count']}")
print(f"Full Prowler rows: {metadata['full_prowler_finding_count']}")
print(f"Filtered resource-group rows: {metadata['filtered_rg_finding_count']}")
print(f"Filtered PASS rows: {metadata['filtered_status_counts']['pass']}")
print(f"Filtered FAIL rows: {metadata['filtered_status_counts']['fail']}")
severity = metadata["severity_counts"]
print(
    "Filtered FAIL severities: "
    f"Critical={severity['critical']} High={severity['high']} "
    f"Medium={severity['medium']} Low={severity['low']}"
)
PY

if [[ "$upload_to_defectdojo" == false ]]; then
  echo "DefectDojo upload status: SKIPPED (--no-defectdojo)"
else
  if [[ -z "${DD_TOKEN:-}" ]]; then
    echo "DD_TOKEN is required for DefectDojo upload." >&2
    exit 1
  fi
  if [[ ! "$DD_TOKEN" =~ ^[A-Za-z0-9._~-]+$ ]]; then
    echo "DD_TOKEN contains characters unsafe for curl's in-memory config." >&2
    exit 1
  fi
  dd_test_id="${DD_TEST_ID:-}"
  if [[ -z "$dd_test_id" ]]; then
    echo "DD_TEST_ID is required for DefectDojo reimport." >&2
    exit 1
  fi
  if [[ ! "$dd_test_id" =~ ^[1-9][0-9]*$ ]]; then
    echo "DD_TEST_ID must be a positive integer." >&2
    exit 1
  fi

  dd_url="${DD_URL:-$DEFAULT_DD_URL}"
  dd_endpoint="${dd_url%/}/api/v2/reimport-scan/"
  curl_tls_options=()
  if [[ -n "${DD_CA_CERT:-}" ]]; then
    if [[ ! -r "$DD_CA_CERT" ]]; then
      echo "DD_CA_CERT is not readable." >&2
      exit 1
    fi
    curl_tls_options+=(--cacert "$DD_CA_CERT")
  fi

  printf 'Reimporting into DefectDojo test=%s.\n' "$dd_test_id"
  http_status="$({ printf 'header = "Authorization: Token %s"\n' "$DD_TOKEN"; } | \
    "$curl_bin" --config - \
      --fail-with-body \
      --silent \
      --show-error \
      --request POST \
      "${curl_tls_options[@]}" \
      --form "scan_type=${DD_SCAN_TYPE}" \
      --form "test=${dd_test_id}" \
      --form 'minimum_severity=Info' \
      --form 'active=true' \
      --form 'verified=true' \
      --form 'close_old_findings=false' \
      --form "file=@${filtered_csv};type=text/csv" \
      --output /dev/null \
      --write-out '%{http_code}' \
      "$dd_endpoint")"
  printf 'DefectDojo upload status: COMPLETED (HTTP %s, close_old_findings=false)\n' \
    "$http_status"
fi

scan_duration_seconds="$(($(date +%s) - scan_started_epoch))"
echo "Scan completion status: COMPLETED"
printf 'Scan duration: %ss\n' "$scan_duration_seconds"
printf 'Full reports: %s\n' "$full_directory"
printf 'Filtered CSV: %s\n' "$filtered_csv"
printf 'Metadata: %s\n' "$metadata_file"
