#!/usr/bin/env bash

set -euo pipefail

if [[ "${REPORT_EVIDENCE_SH_LOADED:-0}" == "1" ]]; then
  return 0
fi
readonly REPORT_EVIDENCE_SH_LOADED=1
readonly REPORT_EVIDENCE_WIDTH=78

report_rule() {
  local character="$1"
  local rule

  printf -v rule '%*s' "$REPORT_EVIDENCE_WIDTH" ''
  printf '%s\n' "${rule// /$character}"
}

report_header() {
  local title="$1"

  printf '\n'
  report_rule '='
  printf ' %s\n' "$title"
  report_rule '='
}

report_section() {
  local title="$1"

  report_rule '-'
  printf '%s\n' "$title"
  report_rule '-'
}

report_field() {
  local label="$1"
  local value="$2"

  printf '%-25s : %s\n' "$label" "$value"
}

report_table_header() {
  local header="$1"

  report_section "$header"
}

report_separator() {
  report_rule '-'
}

report_footer() {
  report_rule '='
}

report_short_commit() {
  local commit="${CIRCLE_SHA1:-}"

  if [[ "$commit" =~ ^[0-9a-fA-F]{8,}$ ]]; then
    printf '%.8s\n' "$commit"
  elif command -v git >/dev/null 2>&1 && commit="$(git rev-parse --verify HEAD 2>/dev/null)"; then
    printf '%.8s\n' "$commit"
  else
    printf 'NOT AVAILABLE\n'
  fi
}

report_pipeline_context() {
  report_field "Pipeline" "${CIRCLE_PIPELINE_NUMBER:-NOT AVAILABLE}"
  report_field "Branch" "${CIRCLE_BRANCH:-NOT AVAILABLE}"
  report_field "Commit" "$(report_short_commit)"
}
