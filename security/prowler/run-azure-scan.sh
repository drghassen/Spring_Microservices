#!/usr/bin/env bash

set -euo pipefail

readonly SCRIPT_DIRECTORY="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly REPOSITORY_ROOT="$(cd "${SCRIPT_DIRECTORY}/../.." && pwd)"

find_prowler() {
  local candidate="${PROWLER_BIN:-prowler}"

  if command -v "$candidate" >/dev/null 2>&1; then
    command -v "$candidate"
    return
  fi
  candidate="${HOME:-}/.local/bin/prowler"
  if [[ -x "$candidate" ]]; then
    printf '%s\n' "$candidate"
    return
  fi

  echo "Prowler is not available on PATH or in the standard pipx user bin directory." >&2
  return 1
}

command -v az >/dev/null 2>&1 || {
  echo "Azure CLI is required." >&2
  exit 1
}
command -v tee >/dev/null 2>&1 || {
  echo "tee is required to retain the scan console log." >&2
  exit 1
}

prowler_bin="$(find_prowler)"
subscription_name="$(az account show --query name --output tsv --only-show-errors)"
subscription_id="$(az account show --query id --output tsv --only-show-errors)"
[[ -n "$subscription_name" && -n "$subscription_id" ]] || {
  echo "Azure CLI did not return an active subscription." >&2
  exit 1
}

timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
scan_started_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
scan_started_epoch="$(date +%s)"
report_directory="${REPOSITORY_ROOT}/reports/prowler/${timestamp}"
mkdir -p "$report_directory"

printf 'Prowler version: %s\n' "$("$prowler_bin" --version)"
printf 'Azure subscription name: %s\n' "$subscription_name"
printf 'Azure subscription ID: %s\n' "$subscription_id"
printf 'Scan start time (UTC): %s\n' "$scan_started_at"
printf 'Report directory: %s\n' "$report_directory"
echo "Starting full read-only Azure subscription assessment."

set +e
"$prowler_bin" azure \
  --az-cli-auth \
  --subscription-id "$subscription_id" \
  --output-formats html csv json-ocsf \
  --output-directory "$report_directory" \
  --ignore-exit-code-3 \
  --no-color 2>&1 | tee "${report_directory}/prowler-console.log"
prowler_status="${PIPESTATUS[0]}"
set -e

scan_duration_seconds="$(($(date +%s) - scan_started_epoch))"
if ((prowler_status != 0)); then
  printf 'Prowler scan completion status: FAILED (exit code %s)\n' "$prowler_status" >&2
  printf 'Scan duration: %ss\n' "$scan_duration_seconds" >&2
  exit "$prowler_status"
fi

echo "Prowler scan completion status: COMPLETED"
printf 'Scan duration: %ss\n' "$scan_duration_seconds"
printf 'Reports generated in: %s\n' "$report_directory"
