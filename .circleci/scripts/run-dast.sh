#!/usr/bin/env bash

set -Eeuo pipefail

source "$(dirname "$0")/lib/application-images.sh"

readonly ZAP_IMAGE="ghcr.io/zaproxy/zaproxy@sha256:781a2bdaea47324e7bab583e2263f21d257b0aee61ed51521a5be45f5f5081ef"
readonly ZAP_REPORT_DIR="$PWD/reports/zap"
readonly ZAP_WORK_DIR="/zap/wrk"
readonly GATEWAY_TARGET_URL="http://gateway:8222"
readonly CLIENT_TARGET_URL="http://client:8080/"
readonly GATEWAY_HEALTH_URL="${GATEWAY_TARGET_URL}/actuator/health"

declare -a SCAN_ERRORS=()
declare -a SECURITY_FINDINGS_HIGH=()

configure_candidate_images
ensure_jq

prepare_zap_report_dir() {
  mkdir -p "$ZAP_REPORT_DIR"
  if [[ "$(stat -c '%u:%g' "$ZAP_REPORT_DIR")" != "$(id -u):$(id -g)" ]]; then
    if (( EUID == 0 )); then
      chown -R "$(id -u):$(id -g)" "$ZAP_REPORT_DIR"
    elif command -v sudo >/dev/null 2>&1; then
      sudo chown -R "$(id -u):$(id -g)" "$ZAP_REPORT_DIR"
    fi
  fi
  find "$ZAP_REPORT_DIR" -type d -exec chmod 0755 {} +
  find "$ZAP_REPORT_DIR" -type f -exec chmod 0644 {} +

  echo "ZAP report directory prepared for Docker bind mount:"
  id
  stat -c '  %a %U:%G %u:%g %n' "$ZAP_REPORT_DIR"
  docker info --format '  Docker security options: {{json .SecurityOptions}}' 2>/dev/null || true
}

log_zap_report_dir_state() {
  echo "ZAP report directory state before scanning $1:"
  ls -la "$ZAP_REPORT_DIR"
}

zap_network() {
  printf '%s_microservices' "$COMPOSE_PROJECT_NAME"
}

zap_docker_base() {
  docker run --rm \
    --user "$(id -u):$(id -g)" \
    --network "$(zap_network)" \
    -e "HOME=${ZAP_WORK_DIR}" \
    -v "${ZAP_REPORT_DIR}:${ZAP_WORK_DIR}:rw" \
    "$ZAP_IMAGE" \
    "$@"
}

record_scan_error() {
  local target_name="$1"
  local reason="$2"

  echo "SCAN_ERROR: ${target_name}: ${reason}" >&2
  SCAN_ERRORS+=("${target_name}: ${reason}")
}

record_security_high() {
  local target_name="$1"
  local high_count="$2"

  echo "SECURITY_FINDING_HIGH: ${target_name}: high_count=${high_count}" >&2
  SECURITY_FINDINGS_HIGH+=("${target_name}: high_count=${high_count}")
}

require_url_with_scheme() {
  local label="$1"
  local url="$2"

  [[ "$url" =~ ^https?:// ]] || {
    record_scan_error "$label" "URL must include http:// or https://: ${url}"
    return 1
  }
}

verify_zap_network_connectivity() {
  echo "Checking ZAP container network connectivity on $(zap_network)."

  zap_docker_base bash -lc "
    set -euo pipefail
    getent hosts gateway
    curl -fsS '${GATEWAY_HEALTH_URL}' >/dev/null
  " || {
    record_scan_error "zap-network" "ZAP container cannot resolve gateway or reach ${GATEWAY_HEALTH_URL}"
    return 1
  }
}

validate_openapi_document() {
  local target_name="$1"
  local specification_url="$2"
  local target_url="$3"
  local openapi_file="${ZAP_REPORT_DIR}/${target_name}.openapi.json"
  local headers_file="${ZAP_REPORT_DIR}/${target_name}.openapi.headers"
  local path_count

  require_url_with_scheme "$target_name OpenAPI" "$specification_url" || return 1
  require_url_with_scheme "$target_name target" "$target_url" || return 1

  echo "Fetching OpenAPI from inside the ZAP network namespace: ${specification_url}"
  zap_docker_base bash -lc "
    set -euo pipefail
    curl -fsSL -D '${ZAP_WORK_DIR}/${target_name}.openapi.headers' '${specification_url}' \
      -o '${ZAP_WORK_DIR}/${target_name}.openapi.json'
  " || {
    record_scan_error "$target_name" "OpenAPI validation: FAILED - cannot fetch ${specification_url}"
    return 1
  }

  [[ -s "$openapi_file" ]] || {
    record_scan_error "$target_name" "OpenAPI validation: FAILED - empty response from ${specification_url}"
    return 1
  }

  if head -c 256 "$openapi_file" | LC_ALL=C grep -q '<[[:alpha:]][^>]*>'; then
    record_scan_error "$target_name" "OpenAPI validation: FAILED - endpoint returned HTML"
    return 1
  fi

  jq -e type "$openapi_file" >/dev/null || {
    record_scan_error "$target_name" "OpenAPI validation: FAILED - response is not valid JSON"
    return 1
  }

  jq -e '
    type == "object"
    and (.openapi | type == "string")
    and (.info | type == "object")
    and (.paths | type == "object")
    and (.paths | length > 0)
    and (.servers | type == "array")
    and (.servers | length > 0)
    and ((.status // empty) == empty)
    and ((.error // empty) == empty)
  ' "$openapi_file" >/dev/null || {
    record_scan_error "$target_name" "OpenAPI validation: FAILED - missing openapi/info/paths/servers or Spring error JSON"
    return 1
  }

  jq -e '
    . as $root
    | def unescape_pointer: gsub("~1"; "/") | gsub("~0"; "~");
      def refpath: ltrimstr("#/") | split("/") | map(unescape_pointer);
      [
        .. | objects | .["$ref"]? | select(type == "string" and startswith("#/")) as $ref
        | select((try ($root | getpath($ref | refpath)) catch null) == null)
      ]
      | length == 0
  ' "$openapi_file" >/dev/null || {
    record_scan_error "$target_name" "OpenAPI validation: FAILED - unresolved local \$ref"
    return 1
  }

  path_count="$(jq '.paths | length' "$openapi_file")"
  echo "OpenAPI validation: OK"
  echo "Service: ${target_name}"
  echo "OpenAPI URL: ${specification_url}"
  echo "Target URL: ${target_url}"
  echo "Number of paths: ${path_count}"
  echo "OpenAPI response headers:"
  sed -n '1,20p' "$headers_file"
}

prepare_zap_report_dir

if [[ "${DAST_STACK_READY:-false}" != "true" ]]; then
  configure_runtime_environment
  export COMPOSE_REPORT_NAME="dast"
  trap collect_compose_logs_and_cleanup EXIT
  wait_for_application_stack
else
  : "${COMPOSE_PROJECT_NAME:?COMPOSE_PROJECT_NAME must be set when DAST_STACK_READY=true}"
fi

gate_high_risk_alerts() {
  local target_name="$1"
  local report_path="reports/zap/${target_name}.json"
  local counts
  local high_count
  local medium_count
  local low_count
  local info_count

  [[ -s "$report_path" ]] || {
    record_scan_error "$target_name" "ZAP did not create a JSON report"
    return 1
  }

  jq -e type "$report_path" >/dev/null || {
    record_scan_error "$target_name" "ZAP created an invalid or corrupted JSON report"
    return 1
  }

  counts="$(jq -r '
    def risk:
      (.riskcode // .riskCode // "0")
      | tostring
      | tonumber;
    def alerts:
      if (.site | type) == "array" then [ .site[]?.alerts[]? ]
      elif (.alerts | type) == "array" then [ .alerts[]? ]
      else [] end;
    alerts as $alerts
    | [
        ($alerts | map(select(risk >= 3)) | length),
        ($alerts | map(select(risk == 2)) | length),
        ($alerts | map(select(risk == 1)) | length),
        ($alerts | map(select(risk == 0)) | length)
      ]
    | @tsv
  ' "$report_path")"
  read -r high_count medium_count low_count info_count <<< "$counts"

  echo "ZAP summary for ${target_name}: scan_success=true high_count=${high_count} medium_count=${medium_count} low_count=${low_count} info_count=${info_count}"

  if (( high_count > 0 )); then
    record_security_high "$target_name" "$high_count"
    return 1
  fi
}

run_zap_scan() {
  local target_name="$1"
  shift
  local zap_exit

  log_zap_report_dir_state "$target_name"
  set +e
  zap_docker_base "$@"
  zap_exit=$?
  set -e

  case "$zap_exit" in
    0|1)
      ;;
    *)
      record_scan_error "$target_name" "ZAP command failed before a reliable security result was available, exit_code=${zap_exit}"
      return 1
      ;;
  esac

  gate_high_risk_alerts "$target_name"
}

zap_baseline() {
  local target_name="$1"
  local target_url="$2"

  require_url_with_scheme "$target_name target" "$target_url" || return 1

  run_zap_scan "$target_name" \
    zap-baseline.py \
    -t "$target_url" \
    -m 2 \
    -I \
    --autooff \
    -J "${ZAP_WORK_DIR}/${target_name}.json" \
    -r "${ZAP_WORK_DIR}/${target_name}.html"
}

zap_api_scan() {
  local target_name="$1"
  local specification_url="$2"
  local target_url="$3"

  validate_openapi_document "$target_name" "$specification_url" "$target_url" || return 1

  # The OpenAPI documents declare localhost as their server. -O must be a full
  # URL because ZAP uses it as the scan target after importing the definition.
  run_zap_scan "$target_name" \
    zap-api-scan.py \
    -t "$specification_url" \
    -f openapi \
    -O "$target_url" \
    -T 10 \
    -I \
    -J "${ZAP_WORK_DIR}/${target_name}.json" \
    -r "${ZAP_WORK_DIR}/${target_name}.html"
}

dast_scan_failed=0

if verify_zap_network_connectivity; then
  if ! zap_baseline client "$CLIENT_TARGET_URL"; then
    dast_scan_failed=1
  fi

  if ! zap_baseline gateway "$GATEWAY_HEALTH_URL"; then
    dast_scan_failed=1
  fi

  declare -A API_DOC_PATHS=(
    [users]="/users/v3/api-docs"
    [games]="/games/v3/api-docs"
    [library]="/library/v3/api-docs"
    [order]="/order/v3/api-docs"
    [payment]="/payment/v3/api-docs"
  )

  for api in users games library order payment; do
    if ! zap_api_scan "${api}-api" "${GATEWAY_TARGET_URL}${API_DOC_PATHS[$api]}" "$GATEWAY_TARGET_URL"; then
      dast_scan_failed=1
    fi
  done
else
  dast_scan_failed=1
fi

if (( dast_scan_failed )); then
  if (( ${#SCAN_ERRORS[@]} > 0 )); then
    printf 'SCAN_ERROR summary:\n' >&2
    printf '  - %s\n' "${SCAN_ERRORS[@]}" >&2
  fi
  if (( ${#SECURITY_FINDINGS_HIGH[@]} > 0 )); then
    printf 'SECURITY_FINDING_HIGH summary:\n' >&2
    printf '  - %s\n' "${SECURITY_FINDINGS_HIGH[@]}" >&2
  fi
  exit 1
fi

echo "OWASP ZAP DAST completed with scan_success=true and high_count=0 for all targets."
