#!/usr/bin/env bash

set -Eeuo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib/application-images.sh"

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
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
readonly DAST_API_PARALLELISM="${DAST_API_PARALLELISM:-3}"
readonly API_WORKER_RESULT_DIR="${ZAP_REPORT_DIR}/api-worker-results"
readonly -a AUTHENTICATED_APIS=(users games library order payment)
readonly -A API_DOC_PATHS=(
  [users]="/users/v3/api-docs"
  [games]="/games/v3/api-docs"
  [library]="/library/v3/api-docs"
  [order]="/order/v3/api-docs"
  [payment]="/payment/v3/api-docs"
)
readonly -A API_TARGET_URLS=(
  [users]="${GATEWAY_TARGET_URL}"
  [games]="${GATEWAY_TARGET_URL}"
  [library]="${GATEWAY_TARGET_URL}"
  [order]="${GATEWAY_TARGET_URL}"
  [payment]="${GATEWAY_TARGET_URL}"
)

DAST_SCRIPT_STARTED_AT=0

declare -a SCAN_ERRORS=()
declare -a SECURITY_FINDINGS_HIGH=()
declare -a API_WORKER_PIDS=()
declare -A API_WORKER_API_BY_PID=()
declare -A API_WORKER_STATUS_BY_API=()

validate_dast_api_parallelism() {
  local parallelism="${1:-$DAST_API_PARALLELISM}"

  [[ "$parallelism" =~ ^[1-3]$ ]] || {
    echo "DAST_API_PARALLELISM must be an integer from 1 to 3; got: ${parallelism}" >&2
    return 1
  }
}

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
  local -a name_args=()

  [[ -n "${DAST_JWT_TOKEN:-}" ]] && env_args+=(-e DAST_JWT_TOKEN)
  [[ -n "${DAST_AUTH_URL_REGEX:-}" ]] && env_args+=(-e DAST_AUTH_URL_REGEX)
  [[ -n "${DAST_AUTH_USERNAME+x}" ]] && env_args+=(-e DAST_AUTH_USERNAME)
  [[ -n "${DAST_AUTH_PASSWORD+x}" ]] && env_args+=(-e DAST_AUTH_PASSWORD)
  [[ -n "${ZAP_DOCKER_NAME:-}" ]] && name_args+=(--name "$ZAP_DOCKER_NAME")

  docker run --rm \
    "${name_args[@]}" \
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

record_dast_auth_failure() {
  local step="$1"
  local http_status="${2:-}"
  local summary_file="${ZAP_REPORT_DIR}/scan-summary.txt"

  mkdir -p "$ZAP_REPORT_DIR"
  if [[ "$http_status" =~ ^[1-5][0-9][0-9]$ ]]; then
    printf 'DAST authentication failed: step=%s http_status=%s\n' "$step" "$http_status" >> "$summary_file"
  else
    printf 'DAST authentication failed: step=%s\n' "$step" >> "$summary_file"
  fi
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
      record_dast_auth_failure "jwt-login"
      record_scan_error "auth" "DAST authentication: failed to obtain JWT from ${AUTH_LOGIN_URL}"
      return 1
    }

    [[ -n "$token" ]] || {
      record_dast_auth_failure "jwt-login-response"
      record_scan_error "auth" "DAST authentication: login response did not contain a JWT"
      return 1
    }

    export DAST_JWT_TOKEN="$token"
    validate_dast_jwt_token "$DAST_JWT_TOKEN" || return 1
    echo "DAST authentication: JWT acquired and validated for authenticated API scans."
    return 0
  fi

  record_dast_auth_failure "credential-selection"
  record_scan_error "auth" "DAST authentication requires an explicit JWT or username/password credentials"
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
    record_dast_auth_failure "jwt-format"
    record_scan_error "auth" "DAST authentication: supplied token is not a compact JWT"
    return 1
  fi

  claims_json="$(jwt_payload_json "$token")" || {
    record_dast_auth_failure "jwt-payload"
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
    record_dast_auth_failure "jwt-claims"
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
    record_dast_auth_failure "gateway-token-validation"
    record_scan_error "auth" "DAST authentication: failed to validate JWT against Gateway"
    return 1
  }

  if [[ "$status" != "200" ]]; then
    record_dast_auth_failure "gateway-token-validation" "$status"
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

finish_dast() {
  local exit_status=$?

  trap - INT TERM
  terminate_api_workers
  report_timing "DAST total" "$DAST_SCRIPT_STARTED_AT"
  if [[ "${DAST_STACK_READY:-false}" == "true" ]]; then
    cleanup_ci_compose_env_file
  else
    collect_compose_logs_and_cleanup
  fi
  return "$exit_status"
}

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

api_worker_container_name() {
  local api="$1"

  printf '%s-zap-%s-api\n' "${COMPOSE_PROJECT_NAME:-dast}" "$api"
}

api_output_paths() {
  local api="$1"
  local target_name="${api}-api"

  printf '%s\n' \
    "${ZAP_REPORT_DIR}/${target_name}.json" \
    "${ZAP_REPORT_DIR}/${target_name}.html" \
    "${ZAP_REPORT_DIR}/${target_name}.openapi.json" \
    "${ZAP_REPORT_DIR}/${target_name}.openapi.headers" \
    "${API_WORKER_RESULT_DIR}/${api}.json"
}

validate_unique_api_output_paths() {
  local api
  local output_path
  local -A seen_paths=()

  for api in "${AUTHENTICATED_APIS[@]}"; do
    while IFS= read -r output_path; do
      [[ -z "${seen_paths[$output_path]+x}" ]] || {
        echo "Duplicate authenticated API output path: ${output_path}" >&2
        return 1
      }
      seen_paths["$output_path"]="$api"
    done < <(api_output_paths "$api")
  done
}

prepare_api_worker_result_dir() {
  [[ "$API_WORKER_RESULT_DIR" == "${ZAP_REPORT_DIR}/api-worker-results" ]] || {
    echo "Refusing to reset unexpected DAST API worker result directory." >&2
    return 1
  }

  rm -rf -- "$API_WORKER_RESULT_DIR"
  mkdir -p "$API_WORKER_RESULT_DIR"
}

api_worker_high_count() {
  local finding
  local high_count=0

  for finding in "${SECURITY_FINDINGS_HIGH[@]}"; do
    if [[ "$finding" =~ high_count=([0-9]+)$ ]]; then
      high_count=$(( high_count + BASH_REMATCH[1] ))
    else
      return 1
    fi
  done
  printf '%s\n' "$high_count"
}

write_api_worker_result() {
  local api="$1"
  local scan_success="$2"
  local high_count="$3"
  local exit_code="$4"
  local elapsed_seconds="$5"
  local result_file="${API_WORKER_RESULT_DIR}/${api}.json"
  local temporary_file

  temporary_file="$(mktemp "${API_WORKER_RESULT_DIR}/.${api}.XXXXXX.tmp")"
  if ! jq -n \
    --arg api "$api" \
    --argjson scanSuccess "$scan_success" \
    --argjson highCount "$high_count" \
    --argjson exitCode "$exit_code" \
    --argjson elapsedSeconds "$elapsed_seconds" \
    '{
      api: $api,
      scan_success: $scanSuccess,
      high_count: $highCount,
      exit_code: $exitCode,
      elapsed_seconds: $elapsedSeconds
    }' > "$temporary_file"; then
    rm -f -- "$temporary_file"
    return 1
  fi

  mv --no-clobber -- "$temporary_file" "$result_file" 2>/dev/null
  if [[ -e "$temporary_file" ]]; then
    rm -f -- "$temporary_file"
    echo "Duplicate worker result rejected for ${api}." >&2
    return 1
  fi
}

run_api_scan_worker() {
  local api="$1"
  local started_at
  local elapsed_seconds
  local high_count=0
  local scan_status=0
  local scan_success=false

  SCAN_ERRORS=()
  SECURITY_FINDINGS_HIGH=()
  export ZAP_DOCKER_NAME="$(api_worker_container_name "$api")"
  started_at="$(timing_now)"

  if zap_api_scan "${api}-api" \
    "${GATEWAY_TARGET_URL}${API_DOC_PATHS[$api]}" \
    "${API_TARGET_URLS[$api]}"; then
    scan_status=0
  else
    scan_status=$?
  fi

  elapsed_seconds="$(timing_elapsed_seconds "$started_at")"
  if ! high_count="$(api_worker_high_count)"; then
    SCAN_ERRORS+=("${api}-api: worker produced an invalid HIGH finding summary")
    high_count=0
    scan_status=1
  fi

  if (( ${#SCAN_ERRORS[@]} == 0 )) && \
    { (( scan_status == 0 )) || (( scan_status == 1 && high_count > 0 )); }; then
    scan_success=true
  fi

  printf 'Timing: %s API scan = %ss\n' "$api" "$elapsed_seconds"
  write_api_worker_result "$api" "$scan_success" "$high_count" "$scan_status" "$elapsed_seconds" || return 125
  return "$scan_status"
}

launch_api_worker() {
  local api="$1"
  local pid

  run_api_scan_worker "$api" &
  pid=$!
  API_WORKER_PIDS+=("$pid")
  API_WORKER_API_BY_PID["$pid"]="$api"
  printf 'Started authenticated API worker: api=%s pid=%s\n' "$api" "$pid"
}

reap_one_api_worker() {
  local completed_pid=""
  local completed_api
  local worker_status
  local pid
  local -a remaining_pids=()

  # Bash wait -n does not select jobs that completed before the call. Reap an
  # already-finished worker first; otherwise block until the next completion.
  for pid in "${API_WORKER_PIDS[@]}"; do
    if ! kill -0 "$pid" 2>/dev/null; then
      completed_pid="$pid"
      if wait "$pid"; then
        worker_status=0
      else
        worker_status=$?
      fi
      break
    fi
  done
  if [[ -z "$completed_pid" ]]; then
    if wait -n -p completed_pid; then
      worker_status=0
    else
      worker_status=$?
    fi
  fi
  completed_pid="${completed_pid:-}"

  [[ -n "$completed_pid" && -n "${API_WORKER_API_BY_PID[$completed_pid]+x}" ]] || {
    echo "Unable to map completed DAST API worker PID." >&2
    return 1
  }

  completed_api="${API_WORKER_API_BY_PID[$completed_pid]}"
  API_WORKER_STATUS_BY_API["$completed_api"]="$worker_status"
  unset 'API_WORKER_API_BY_PID[$completed_pid]'
  for pid in "${API_WORKER_PIDS[@]}"; do
    [[ "$pid" == "$completed_pid" ]] || remaining_pids+=("$pid")
  done
  API_WORKER_PIDS=("${remaining_pids[@]}")
  printf 'Completed authenticated API worker: api=%s exit_code=%s\n' "$completed_api" "$worker_status"
}

terminate_api_workers() {
  local pid
  local api
  local container_name

  for pid in "${API_WORKER_PIDS[@]:-}"; do
    [[ -n "$pid" ]] || continue
    api="${API_WORKER_API_BY_PID[$pid]:-}"
    if [[ -n "$api" ]] && command -v docker >/dev/null 2>&1; then
      container_name="$(api_worker_container_name "$api")"
      docker rm --force "$container_name" >/dev/null 2>&1 || true
    fi
    kill "$pid" 2>/dev/null || true
  done
  for pid in "${API_WORKER_PIDS[@]:-}"; do
    [[ -n "$pid" ]] || continue
    wait "$pid" 2>/dev/null || true
  done

  API_WORKER_PIDS=()
  API_WORKER_API_BY_PID=()
}

handle_dast_signal() {
  local exit_status="$1"

  trap - INT TERM
  terminate_api_workers
  exit "$exit_status"
}

report_api_batch_resources() {
  local phase="$1"

  printf 'DAST API batch resource diagnostics (%s):\n' "$phase"
  if command -v free >/dev/null 2>&1; then
    free -h || true
  else
    echo "free is unavailable; memory diagnostics skipped."
  fi
  if command -v nproc >/dev/null 2>&1; then
    printf 'Available processors: '
    nproc || true
  else
    echo "nproc is unavailable; CPU diagnostics skipped."
  fi
  if command -v docker >/dev/null 2>&1; then
    docker stats --no-stream \
      --format 'container={{.Name}} cpu={{.CPUPerc}} memory={{.MemUsage}}' || true
  else
    echo "docker is unavailable; container diagnostics skipped."
  fi
}

aggregate_api_worker_results() {
  local api
  local result_file
  local result_api
  local scan_success
  local high_count
  local exit_code
  local elapsed_seconds
  local actual_file_count
  local batch_failed=0

  actual_file_count="$(find "$API_WORKER_RESULT_DIR" -maxdepth 1 -type f | wc -l)"
  if [[ "$actual_file_count" != "${#AUTHENTICATED_APIS[@]}" ]]; then
    record_scan_error "api-worker-results" \
      "expected ${#AUTHENTICATED_APIS[@]} result files, found ${actual_file_count}"
    batch_failed=1
  fi

  for api in "${AUTHENTICATED_APIS[@]}"; do
    result_file="${API_WORKER_RESULT_DIR}/${api}.json"
    if [[ ! -s "$result_file" ]]; then
      record_scan_error "${api}-api" "missing worker result"
      batch_failed=1
      continue
    fi
    if ! jq -e --arg expectedApi "$api" '
      (keys | sort) == (["api", "elapsed_seconds", "exit_code", "high_count", "scan_success"] | sort)
      and .api == $expectedApi
      and (.scan_success | type) == "boolean"
      and (.high_count | type) == "number"
      and (.high_count | floor) == .high_count
      and .high_count >= 0
      and (.exit_code | type) == "number"
      and (.exit_code | floor) == .exit_code
      and .exit_code >= 0 and .exit_code <= 255
      and (.elapsed_seconds | type) == "number"
      and (.elapsed_seconds | floor) == .elapsed_seconds
      and .elapsed_seconds >= 0
    ' "$result_file" >/dev/null; then
      record_scan_error "${api}-api" "malformed or unsafe worker result"
      batch_failed=1
      continue
    fi

    read -r result_api scan_success high_count exit_code elapsed_seconds < <(
      jq -r '[.api, .scan_success, .high_count, .exit_code, .elapsed_seconds] | @tsv' "$result_file"
    )
    if [[ -z "${API_WORKER_STATUS_BY_API[$api]+x}" || \
      "${API_WORKER_STATUS_BY_API[$api]}" != "$exit_code" ]]; then
      record_scan_error "${api}-api" "worker exit status does not match its result"
      batch_failed=1
    fi
    if [[ "$scan_success" != "true" ]]; then
      record_scan_error "${api}-api" "worker reported scan failure, exit_code=${exit_code}"
      batch_failed=1
    elif (( exit_code != 0 && high_count == 0 )); then
      record_scan_error "${api}-api" "worker returned non-zero without a HIGH finding"
      batch_failed=1
    fi
    if (( high_count > 0 )); then
      record_security_high "${api}-api" "$high_count"
      batch_failed=1
    fi
    printf 'Authenticated API result: api=%s scan_success=%s high_count=%s exit_code=%s elapsed_seconds=%s\n' \
      "$result_api" "$scan_success" "$high_count" "$exit_code" "$elapsed_seconds"
  done

  return "$batch_failed"
}

run_authenticated_api_batch() {
  local batch_started_at
  local next_api_index=0

  validate_dast_api_parallelism || return 1
  validate_unique_api_output_paths || return 1
  prepare_api_worker_result_dir || return 1
  API_WORKER_PIDS=()
  API_WORKER_API_BY_PID=()
  API_WORKER_STATUS_BY_API=()
  batch_started_at="$(timing_now)"
  report_api_batch_resources "before"

  while (( next_api_index < ${#AUTHENTICATED_APIS[@]} || ${#API_WORKER_PIDS[@]} > 0 )); do
    while (( next_api_index < ${#AUTHENTICATED_APIS[@]} && \
      ${#API_WORKER_PIDS[@]} < DAST_API_PARALLELISM )); do
      launch_api_worker "${AUTHENTICATED_APIS[$next_api_index]}"
      next_api_index=$(( next_api_index + 1 ))
    done
    if (( ${#API_WORKER_PIDS[@]} > 0 )); then
      if ! reap_one_api_worker; then
        terminate_api_workers
        record_scan_error "api-worker-pool" "failed to reap an authenticated API worker"
        return 1
      fi
    fi
  done

  report_api_batch_resources "after"
  report_timing "authenticated API parallel batch" "$batch_started_at"
  aggregate_api_worker_results
}

main() {
  local dast_scan_failed=0
  local auth_ready=0
  local network_started_at
  local frontend_started_at
  local gateway_started_at
  local authentication_started_at

  DAST_SCRIPT_STARTED_AT="$(timing_now)"
  configure_candidate_images
  ensure_jq
  validate_dast_api_parallelism
  prepare_zap_report_dir

  if [[ "${DAST_STACK_READY:-false}" != "true" ]]; then
    configure_runtime_environment
    create_ci_compose_env_file
    use_ci_dast_fixture_credentials
    export COMPOSE_REPORT_NAME="dast"
    # finish_dast preserves Compose log collection, stack teardown, and
    # cleanup_ci_compose_env_file on every EXIT path.
    trap finish_dast EXIT
    trap 'handle_dast_signal 130' INT
    trap 'handle_dast_signal 143' TERM
    wait_for_application_stack
  else
    : "${COMPOSE_PROJECT_NAME:?COMPOSE_PROJECT_NAME must be set when DAST_STACK_READY=true}"
    create_ci_compose_env_file
    trap finish_dast EXIT
    trap 'handle_dast_signal 130' INT
    trap 'handle_dast_signal 143' TERM
  fi

  network_started_at="$(timing_now)"
  if verify_zap_network_connectivity; then
    report_timing "DAST network connectivity" "$network_started_at"
    frontend_started_at="$(timing_now)"
    if ! zap_frontend_full_scan client "$CLIENT_TARGET_URL"; then
      dast_scan_failed=1
    fi
    report_timing "frontend full scan" "$frontend_started_at"

    gateway_started_at="$(timing_now)"
    if ! zap_baseline gateway "$GATEWAY_HEALTH_URL"; then
      dast_scan_failed=1
    fi
    report_timing "Gateway baseline" "$gateway_started_at"

    authentication_started_at="$(timing_now)"
    if configure_dast_jwt_token; then
      auth_ready=1
    else
      dast_scan_failed=1
    fi
    report_timing "authentication" "$authentication_started_at"

    if (( auth_ready )); then
      if ! run_authenticated_api_batch; then
        dast_scan_failed=1
      fi
    else
      echo "Skipping authenticated API scans because DAST authentication failed." >&2
    fi
  else
    report_timing "DAST network connectivity" "$network_started_at"
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
    return 1
  fi

  echo "OWASP ZAP DAST completed with scan_success=true and high_count=0 for all targets."
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
