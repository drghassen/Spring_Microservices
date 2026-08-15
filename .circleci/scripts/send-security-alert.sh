#!/usr/bin/env bash

# This script is intentionally non-blocking: a failure to send an alert must
# never mask the original security-gate failure that triggered it.
set -euo pipefail

readonly AZURE_CLI_IMAGE="mcr.microsoft.com/azure-cli:2.80.0@sha256:b138e1125a95b7e7bc000f8458f1bb206b7836b11eca38a3633cf135619a99ca"

usage() {
  echo "Usage: $0 --scanner <name> --reports <file-or-directory>" >&2
}

scanner=""
reports_path=""

while (($#)); do
  case "$1" in
    --scanner)
      scanner="${2:-}"
      shift 2
      ;;
    --reports)
      reports_path="${2:-}"
      shift 2
      ;;
    *)
      usage
      exit 0
      ;;
  esac
done

if [[ -z "$scanner" || -z "$reports_path" ]]; then
  usage
  exit 0
fi

for required_variable in \
  AZURE_COMMUNICATION_CONNECTION_STRING \
  ACS_EMAIL_SENDER \
  SECURITY_ALERT_RECIPIENTS; do
  if [[ -z "${!required_variable:-}" ]]; then
    echo "Security alert skipped: ${required_variable} is not set in the security-alerts context." >&2
    exit 0
  fi
done

slug="$(printf '%s' "$scanner" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9' '-')"
readonly summary_path="reports/security-alerts/${slug}-failure.txt"
mkdir -p "$(dirname "$summary_path")"

append_json_findings() {
  local report="$1"

  if command -v jq >/dev/null 2>&1; then
    jq -r '
      [
        .. | objects
        | select(
            .Severity? == "HIGH" or .Severity? == "CRITICAL" or
            .RuleSeverity? == "HIGH" or .RuleSeverity? == "CRITICAL" or
            (.riskcode? != null and (.riskcode | tonumber) >= 3)
          )
        | "\(.Severity // .RuleSeverity // "HIGH") | \(.VulnerabilityID // .AVDID // .RuleID // .ID // .alert // "finding") | \(.PkgName // .Title // .Message // .Cause // .desc // "")"
      ] | unique | .[:50][]
    ' "$report" 2>/dev/null || true
  else
    # The raw report remains available as a CircleCI artifact; this fallback
    # still gives the recipient enough context when jq is unavailable.
    fold -w 160 "$report" | head -n 80 || true
  fi
}

{
  printf 'Security gate failed: %s\n\n' "$scanner"
  printf 'Project: %s\n' "${CIRCLE_PROJECT_REPONAME:-unknown}"
  printf 'Branch: %s\n' "${CIRCLE_BRANCH:-unknown}"
  printf 'Commit: %s\n' "${CIRCLE_SHA1:-unknown}"
  printf 'Workflow: %s\n' "${CIRCLE_WORKFLOW_ID:-unknown}"
  printf 'CircleCI job: %s\n\n' "${CIRCLE_BUILD_URL:-unavailable}"
  printf 'The original scanner failure remains blocking. Relevant findings follow:\n\n'

  if [[ -d "$reports_path" ]]; then
    mapfile -t reports < <(find "$reports_path" -type f \( -name '*.json' -o -name '*.log' -o -name '*.txt' \) | sort)
  elif [[ -f "$reports_path" ]]; then
    reports=("$reports_path")
  else
    reports=()
  fi

  if ((${#reports[@]} == 0)); then
    printf 'No machine-readable report was produced. Consult the CircleCI job log above for the infrastructure or scanner error.\n'
  fi

  for report in "${reports[@]}"; do
    printf '\n===== %s =====\n' "$report"
    case "$report" in
      *.json)
        append_json_findings "$report"
        ;;
      *)
        tail -n 80 "$report" || true
        ;;
    esac
  done
} > "$summary_path"

readonly subject="[SECURITY FAILED] ${scanner} — ${CIRCLE_PROJECT_REPONAME:-project} (${CIRCLE_BRANCH:-unknown})"

if docker run --rm \
  -e AZURE_COMMUNICATION_CONNECTION_STRING \
  -e ACS_EMAIL_SENDER \
  -e SECURITY_ALERT_RECIPIENTS \
  -e ALERT_SUBJECT="$subject" \
  -v "$PWD:/workspace:ro" \
  "$AZURE_CLI_IMAGE" \
  sh -ec '
    az extension add --name communication --only-show-errors >/dev/null
    body="$(cat /workspace/'"$summary_path"')"
    az communication email send \
      --sender "$ACS_EMAIL_SENDER" \
      --to "$SECURITY_ALERT_RECIPIENTS" \
      --subject "$ALERT_SUBJECT" \
      --text "$body" \
      --attachments "/workspace/'"$summary_path"'" \
      --attachment-types txt \
      --importance high \
      --only-show-errors \
      --output none
  '; then
  echo "Security alert sent for ${scanner}."
else
  echo "Security alert delivery failed; the original scanner failure is preserved." >&2
fi

exit 0
