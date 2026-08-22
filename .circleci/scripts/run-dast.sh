#!/usr/bin/env bash

set -Eeuo pipefail

source "$(dirname "$0")/lib/application-images.sh"

readonly SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
readonly ZAP_IMAGE="ghcr.io/zaproxy/zaproxy@sha256:781a2bdaea47324e7bab583e2263f21d257b0aee61ed51521a5be45f5f5081ef"
readonly ZAP_REPORT_DIR="$PWD/reports/zap"
readonly ZAP_WORK_DIR="/zap/wrk"
readonly ZAP_SCRIPT_DIR="/zap/scripts"
readonly ZAP_JWT_AUTH_HOOK="${ZAP_SCRIPT_DIR}/zap-jwt-auth-hook.py"
readonly GATEWAY_TARGET_URL="http://gateway:8222"
readonly CLIENT_TARGET_URL="http://client:8080/"
readonly GATEWAY_HEALTH_URL="${GATEWAY_TARGET_URL}/actuator/health"
readonly AUTH_LOGIN_URL="${GATEWAY_TARGET_URL}/api/v1/auth/login"
readonly AUTH_VALIDATION_URL_BASE="${GATEWAY_TARGET_URL}/api/v1/users/username"

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
  # The ZAP image runs as its internal "zap" user. CircleCI owns the bind
  # mount as "circleci", so make the report mount writable by the container.
  find "$ZAP_REPORT_DIR" -type d -exec chmod 0777 {} +
  find "$ZAP_REPORT_DIR" -type f -exec chmod 0666 {} +

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
  local -a env_args=()

  [[ -n "${DAST_JWT_TOKEN:-}" ]] && env_args+=(-e DAST_JWT_TOKEN)
  [[ -n "${DAST_AUTH_URL_REGEX:-}" ]] && env_args+=(-e DAST_AUTH_URL_REGEX)
  [[ -n "${DAST_AUTH_USERNAME+x}" ]] && env_args+=(-e DAST_AUTH_USERNAME)
  [[ -n "${DAST_AUTH_PASSWORD+x}" ]] && env_args+=(-e DAST_AUTH_PASSWORD)

  docker run --rm \
    --network "$(zap_network)" \
    "${env_args[@]}" \
    -v "${ZAP_REPORT_DIR}:${ZAP_WORK_DIR}:rw" \
    -v "${SCRIPT_DIR}:${ZAP_SCRIPT_DIR}:ro" \
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

configure_dast_jwt_token() {
  local token

  if [[ -n "${DAST_JWT_TOKEN:-}" ]]; then
    echo "DAST authentication: using JWT from DAST_JWT_TOKEN."
    validate_dast_jwt_token "$DAST_JWT_TOKEN"
    return $?
  fi

  if [[ -n "${DAST_AUTH_USERNAME:-}" && -n "${DAST_AUTH_PASSWORD+x}" ]]; then
    echo "DAST authentication: requesting JWT with DAST_AUTH_USERNAME/DAST_AUTH_PASSWORD."
    token="$(zap_docker_base bash -lc "
      set -euo pipefail
      jq -cn --arg username \"\$DAST_AUTH_USERNAME\" --arg password \"\$DAST_AUTH_PASSWORD\" \
        '{username: \$username, password: \$password}' \
        | curl -fsS -H 'Content-Type: application/json' --data-binary @- '${AUTH_LOGIN_URL}' \
        | jq -er '.message | select(type == \"string\" and length > 0)'
    ")" || {
      record_scan_error "auth" "DAST authentication: failed to obtain JWT from ${AUTH_LOGIN_URL}"
      return 1
    }

    [[ -n "$token" ]] || {
      record_scan_error "auth" "DAST authentication: login response did not contain a JWT"
      return 1
    }

    export DAST_JWT_TOKEN="$token"
    validate_dast_jwt_token "$DAST_JWT_TOKEN" || return 1
    echo "DAST authentication: JWT acquired and validated for authenticated API scans."
    return 0
  fi

  record_scan_error "auth" "DAST authentication requires DAST_JWT_TOKEN or DAST_AUTH_USERNAME/DAST_AUTH_PASSWORD CircleCI secrets"
  return 1
}

jwt_payload_json() {
  local token="$1"

  jq -Rer '
    split(".") | select(length == 3) | .[1]
    | gsub("-"; "+")
    | gsub("_"; "/")
    | . as $payload
    | ($payload | length % 4) as $remainder
    | if $remainder == 0 then $payload
      elif $remainder == 2 then $payload + "=="
      elif $remainder == 3 then $payload + "="
      else error("invalid JWT base64url payload")
      end
    | @base64d
    | fromjson
  ' <<< "$token"
}

validate_dast_jwt_token() {
  local token="$1"
  local claims_json
  local subject
  local encoded_subject
  local validation_url
  local status
  local now

  if [[ ! "$token" =~ ^[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+$ ]]; then
    record_scan_error "auth" "DAST authentication: supplied token is not a compact JWT"
    return 1
  fi

  claims_json="$(jwt_payload_json "$token")" || {
    record_scan_error "auth" "DAST authentication: JWT payload is not valid JSON"
    return 1
  }

  now="$(date +%s)"
  jq -e --argjson now "$now" '
    type == "object"
    and (.sub | type == "string" and length > 0)
    and (.exp | type == "number" and . > ($now + 60))
    and (.roles | type == "array" and length > 0)
  ' <<< "$claims_json" >/dev/null || {
    record_scan_error "auth" "DAST authentication: JWT is missing required claims or expires too soon"
    return 1
  }

  subject="$(jq -r '.sub' <<< "$claims_json")"
  encoded_subject="$(jq -nr --arg value "$subject" '$value | @uri')"
  validation_url="${AUTH_VALIDATION_URL_BASE}/${encoded_subject}"

  status="$(zap_docker_base bash -lc "
    set -euo pipefail
    curl -sS -o /dev/null -w '%{http_code}' \
      -H \"Authorization: Bearer \${DAST_JWT_TOKEN}\" \
      '${validation_url}'
  ")" || {
    record_scan_error "auth" "DAST authentication: failed to validate JWT against Gateway"
    return 1
  }

  if [[ "$status" != "200" ]]; then
    record_scan_error "auth" "DAST authentication: Gateway rejected JWT validation request with HTTP ${status}"
    return 1
  fi
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
    and (has("status") | not)
    and (has("error") | not)
  ' "$openapi_file" >/dev/null || {
    echo "OpenAPI validation response preview for ${target_name}:" >&2
    jq -c '{
      openapi,
      title: .info.title,
      servers,
      paths_type: (.paths | type),
      path_count: (try (.paths | length) catch null),
      status,
      error,
      path,
      message
    }' "$openapi_file" >&2 || true
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

zap_frontend_full_scan() {
  local target_name="$1"
  local target_url="$2"

  require_url_with_scheme "$target_name target" "$target_url" || return 1

  run_zap_scan "$target_name" \
    zap-full-scan.py \
    -t "$target_url" \
    -m 2 \
    -j \
    --client-spider \
    -I \
    -J "${ZAP_WORK_DIR}/${target_name}.json" \
    -r "${ZAP_WORK_DIR}/${target_name}.html"
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
    -J "${target_name}.json" \
    -r "${target_name}.html"
}

zap_api_scan() {
  local target_name="$1"
  local specification_url="$2"
  local target_url="$3"

  [[ -n "${DAST_JWT_TOKEN:-}" ]] || {
    record_scan_error "$target_name" "Authenticated API scan blocked because DAST authentication did not produce a validated JWT"
    return 1
  }

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
    --hook "$ZAP_JWT_AUTH_HOOK" \
    -J "${ZAP_WORK_DIR}/${target_name}.json" \
    -r "${ZAP_WORK_DIR}/${target_name}.html"
}

dast_scan_failed=0
auth_ready=0

if verify_zap_network_connectivity; then
  if ! zap_frontend_full_scan client "$CLIENT_TARGET_URL"; then
    dast_scan_failed=1
  fi

  if ! zap_baseline gateway "$GATEWAY_HEALTH_URL"; then
    dast_scan_failed=1
  fi

  if configure_dast_jwt_token; then
    auth_ready=1
  else
    dast_scan_failed=1
  fi

  declare -A API_DOC_PATHS=(
    [users]="/users/v3/api-docs"
    [games]="/games/v3/api-docs"
    [library]="/library/v3/api-docs"
    [order]="/order/v3/api-docs"
    [payment]="/payment/v3/api-docs"
  )

  declare -A API_TARGET_URLS=(
    [users]="${GATEWAY_TARGET_URL}"
    [games]="${GATEWAY_TARGET_URL}"
    [library]="${GATEWAY_TARGET_URL}"
    [order]="${GATEWAY_TARGET_URL}"
    [payment]="${GATEWAY_TARGET_URL}"
  )

  if (( auth_ready )); then
    for api in users games library order payment; do
      if ! zap_api_scan "${api}-api" "${GATEWAY_TARGET_URL}${API_DOC_PATHS[$api]}" "${API_TARGET_URLS[$api]}"; then
        dast_scan_failed=1
      fi
    done
  else
    echo "Skipping authenticated API scans because DAST authentication failed." >&2
  fi
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
