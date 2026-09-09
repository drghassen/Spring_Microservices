#!/usr/bin/env bash

set -euo pipefail

if [[ "${SONAR_EVIDENCE_SH_LOADED:-0}" == "1" ]]; then
  return 0
fi
readonly SONAR_EVIDENCE_SH_LOADED=1

# shellcheck source=report-evidence.sh
source "$(dirname "${BASH_SOURCE[0]}")/report-evidence.sh"

sonar_quality_gate_response_is_valid() {
  local response_file="$1"

  [[ -s "$response_file" ]] && jq -e '
    .projectStatus.status as $status
    | ($status == "OK" or $status == "ERROR" or $status == "WARN" or $status == "NONE")
    and ((.projectStatus.conditions // []) | type == "array")
  ' "$response_file" >/dev/null 2>&1
}

sonar_fetch_quality_gate() {
  local project_key="$1"
  local token="$2"
  local response_file="$3"

  curl --fail --silent --show-error \
    --user "${token}:" \
    --get "${SONAR_HOST_URL%/}/api/qualitygates/project_status" \
    --data-urlencode "projectKey=${project_key}" \
    --output "$response_file"

  sonar_quality_gate_response_is_valid "$response_file"
}

sonar_scanner_result() {
  local scanner_status="$1"
  local scanner_log="$2"

  if (( scanner_status == 0 )); then
    printf 'PASSED\n'
  elif grep -Fq 'QUALITY GATE STATUS: FAILED' "$scanner_log"; then
    printf 'FAILED\n'
  else
    printf 'ERROR\n'
  fi
}

sonar_gate_result_from_response() {
  local response_file="$1"
  local api_status

  api_status="$(jq -r '.projectStatus.status' "$response_file")"
  case "$api_status" in
    OK) printf 'PASSED\n' ;;
    ERROR) printf 'FAILED\n' ;;
    WARN) printf 'WARNING\n' ;;
    *) printf 'NOT AVAILABLE\n' ;;
  esac
}

sonar_required_value() {
  local comparator="$1"
  local threshold="$2"

  case "$comparator" in
    LT) printf '>= %s\n' "$threshold" ;;
    GT) printf '<= %s\n' "$threshold" ;;
    EQ) printf '= %s\n' "$threshold" ;;
    NE) printf '!= %s\n' "$threshold" ;;
    *) printf '%s %s\n' "$comparator" "$threshold" ;;
  esac
}

sonar_condition_result() {
  local condition_status="$1"

  case "$condition_status" in
    OK) printf 'PASS\n' ;;
    ERROR) printf 'FAIL\n' ;;
    WARN) printf 'WARN\n' ;;
    *) printf '%s\n' "$condition_status" ;;
  esac
}

sonar_last_numeric_log_value() {
  local pattern="$1"
  local scanner_log="$2"
  local match
  local value

  match="$(grep -Eo "$pattern" "$scanner_log" | tail -n 1 || true)"
  value="$(grep -Eo '[0-9]+' <<< "$match" | head -n 1 || true)"
  printf '%s\n' "${value:-NOT AVAILABLE}"
}

report_sonar_evidence() {
  local title="$1"
  local project_key="$2"
  local coverage_evidence="$3"
  local scanner_status="$4"
  local scanner_log="$5"
  local response_file="$6"
  local scanner_result
  local gate_result
  local api_result="NOT AVAILABLE"
  local analysis_state="INCOMPLETE"
  local indexed_files
  local typescript_files
  local failed_conditions="NOT AVAILABLE"
  local metric
  local actual
  local comparator
  local threshold
  local condition_status
  local required
  local result

  scanner_result="$(sonar_scanner_result "$scanner_status" "$scanner_log")"
  gate_result="$scanner_result"
  indexed_files="$(sonar_last_numeric_log_value '([0-9]+) files indexed' "$scanner_log")"
  typescript_files="$(sonar_last_numeric_log_value 'Analyzed ([0-9]+) file.* with current program' "$scanner_log")"

  if grep -Fq 'Analysis report uploaded' "$scanner_log"; then
    analysis_state="UPLOADED"
  fi

  if sonar_quality_gate_response_is_valid "$response_file"; then
    api_result="AVAILABLE"
    gate_result="$(sonar_gate_result_from_response "$response_file")"
    failed_conditions="$(jq '[.projectStatus.conditions[]? | select(.status == "ERROR")] | length' "$response_file")"
  fi

  report_header "$title"
  report_pipeline_context
  report_field "Project key" "$project_key"
  report_field "Analysis report" "$analysis_state"
  report_field "Files indexed" "$indexed_files"
  if [[ "$typescript_files" != "NOT AVAILABLE" ]]; then
    report_field "TypeScript files" "$typescript_files analyzed"
  fi
  report_field "Coverage evidence" "$coverage_evidence"
  report_field "Quality Gate API" "$api_result"
  report_field "Scanner exit code" "$scanner_status"

  if [[ "$api_result" == "AVAILABLE" ]]; then
    printf '\n'
    report_table_header "Metric                              Actual       Required     Status"
    while IFS=$'\t' read -r metric actual comparator threshold condition_status; do
      required="$(sonar_required_value "$comparator" "$threshold")"
      result="$(sonar_condition_result "$condition_status")"
      printf '%-34s %10s %14s %10s\n' "$metric" "$actual" "$required" "$result"
    done < <(jq -r '
      .projectStatus.conditions[]?
      | [
          .metricKey,
          (.actualValue // "N/A"),
          (.comparator // "N/A"),
          (.errorThreshold // "N/A"),
          (.status // "N/A")
        ]
      | @tsv
    ' "$response_file")
    report_separator
    report_field "Failed conditions" "$failed_conditions"
  fi

  case "$gate_result" in
    PASSED)
      report_field "Pipeline gate" "OPEN"
      report_field "Action" "None"
      ;;
    FAILED)
      report_field "Pipeline gate" "BLOCKED"
      report_field "Action" "Fix the failed metric(s) listed above"
      ;;
    *)
      report_field "Pipeline gate" "BLOCKED - TECHNICAL ERROR"
      report_field "Action" "Inspect the scanner log and SonarQube Compute Engine"
      ;;
  esac
  report_field "QUALITY GATE" "$gate_result"
  report_footer
}
