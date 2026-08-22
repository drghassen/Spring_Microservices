#!/usr/bin/env bash

set -euo pipefail

readonly APP_SERVICES=(
  config-server discovery-service gateway games-service library-service
  order-service payment-service user-service client
)

readonly EXPECTED_EUREKA_APPLICATIONS=(
  GATEWAY USER-SERVICE GAMES-SERVICE LIBRARY-SERVICE ORDER-SERVICE PAYMENT-SERVICE
)
readonly GATEWAY_DISCOVERY_WAIT_ATTEMPTS="${GATEWAY_DISCOVERY_WAIT_ATTEMPTS:-24}"
readonly GATEWAY_DISCOVERY_WAIT_INTERVAL_SECONDS="${GATEWAY_DISCOVERY_WAIT_INTERVAL_SECONDS:-5}"
readonly GATEWAY_DISCOVERY_HEALTH_URL="${GATEWAY_DISCOVERY_HEALTH_URL:-http://localhost:8222/actuator/health}"

configure_candidate_images() {
  : "${IMAGE_TAG:?IMAGE_TAG must be defined by CircleCI config as build-<< pipeline.number >>}"

  [[ "$IMAGE_TAG" =~ ^build-[0-9]+$ ]] || {
    echo "IMAGE_TAG must match build-<pipeline.number>; got: ${IMAGE_TAG}" >&2
    exit 1
  }

  export IMAGE_TAG
  export IMAGE_REPOSITORY_PREFIX="${IMAGE_REPOSITORY_PREFIX:-ci.local}"
}

candidate_image_references() {
  local service
  local services=("$@")

  if (( ${#services[@]} == 0 )); then
    services=("${APP_SERVICES[@]}")
  fi

  for service in "${services[@]}"; do
    printf '%s/%s:%s\n' "$IMAGE_REPOSITORY_PREFIX" "$service" "$IMAGE_TAG"
  done
}

ensure_zstd() {
  if ! command -v zstd >/dev/null 2>&1; then
    sudo apt-get update
    sudo apt-get install -y zstd
  fi
}

ensure_jq() {
  if ! command -v jq >/dev/null 2>&1; then
    sudo apt-get update
    sudo apt-get install -y jq
  fi
}

ensure_curl() {
  command -v curl >/dev/null 2>&1 || {
    echo "curl is required for container integration checks." >&2
    exit 1
  }
}

configure_runtime_environment() {
  : "${CIRCLE_BUILD_NUM:?CIRCLE_BUILD_NUM must be defined by CircleCI}"

  if [[ -z "${JWT_SECRET:-}" ]]; then
    export JWT_SECRET="$(openssl rand -base64 48)"
  else
    export JWT_SECRET
  fi
  export COMPOSE_PROJECT_NAME="ci${CIRCLE_BUILD_NUM}"
  if [[ "${DAST_AUTH_USERNAME:-}" == "admin" && -n "${DAST_AUTH_PASSWORD+x}" && -z "${ADMIN_PASSWORD+x}" ]]; then
    export ADMIN_PASSWORD="$DAST_AUTH_PASSWORD"
  fi
}

collect_compose_logs_and_cleanup() {
  local report_name="${COMPOSE_REPORT_NAME:-docker-compose}"
  local container_ids

  mkdir -p reports
  docker compose ps --all > "reports/${report_name}.ps.log" 2>&1 || true

  if container_ids="$(docker compose ps --all --quiet 2>/dev/null)"; then
    while IFS= read -r container_id; do
      [[ -n "$container_id" ]] || continue
      docker inspect --format '{{.Name}} status={{.State.Status}} exit_code={{.State.ExitCode}} health={{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' \
        "$container_id"
    done <<< "$container_ids" > "reports/${report_name}.health.log" 2>&1 || true
  fi

  docker compose logs --no-color > "reports/${report_name}.log" || true
  docker compose down --volumes --remove-orphans || true
}

eureka_registration_report() {
  local eureka_apps="$1"
  local expected_json

  printf -v expected_json '%s' "${EXPECTED_EUREKA_APPLICATIONS[*]}"
  jq -r --arg expected_list "$expected_json" '
    def expected_applications: $expected_list | split(" ");
    def applications:
      if (.applications | type) != "object" then
        error("missing applications object")
      elif (.applications.application | type) == "array" then
        .applications.application
      elif (.applications.application | type) == "object" then
        [.applications.application]
      else
        error("missing applications.application collection")
      end;
    def instance_count:
      if . == null then 0
      elif type == "array" then length
      elif type == "object" then 1
      else 0
      end;

    (applications) as $applications
    | expected_applications[] as $expected
    | ($applications
       | map(select(.name == $expected) | (.instance | instance_count))
       | add // 0) as $count
    | "\($expected)\t\($count)"
  ' <<< "$eureka_apps"
}

validate_eureka_registrations() {
  local eureka_apps="$1"
  local registration_report
  local application
  local instance_count
  local registrations_valid=0

  if ! registration_report="$(eureka_registration_report "$eureka_apps")"; then
    echo "Eureka registration check: response is empty, invalid JSON, or has no applications collection." >&2
    return 1
  fi

  while IFS=$'\t' read -r application instance_count; do
    if [[ "$instance_count" == "1" ]]; then
      echo "Eureka registration check: ${application}=1 instance."
    else
      echo "Eureka registration check: ${application} expected 1 instance, observed ${instance_count}." >&2
      registrations_valid=1
    fi
  done <<< "$registration_report"

  return "$registrations_valid"
}

assert_http_status() {
  local label="$1"
  local expected_status="$2"
  local url="$3"
  local actual_status
  local curl_exit=0
  shift 3

  actual_status="$(curl --silent --show-error --output /dev/null --write-out '%{http_code}' \
    --connect-timeout 5 --max-time 20 --retry 3 --retry-delay 2 --retry-connrefused \
    "$@" "$url")" || curl_exit=$?

  if (( curl_exit != 0 )); then
    echo "Smoke check FAILED: ${label}: request could not be completed (curl exit ${curl_exit}, observed HTTP ${actual_status:-000})." >&2
    diagnose_smoke_failure "$label" "$url" "$curl_exit" "${actual_status:-000}"
    return 1
  fi

  if [[ "$actual_status" != "$expected_status" ]]; then
    echo "Smoke check FAILED: ${label}: expected HTTP ${expected_status}, observed HTTP ${actual_status}." >&2
    diagnose_smoke_failure "$label" "$url" 0 "$actual_status"
    return 1
  fi

  echo "Smoke check OK: ${label}: HTTP ${actual_status}."
}

diagnose_smoke_failure() {
  local label="$1"
  local url="$2"
  local curl_exit="$3"
  local actual_status="$4"

  echo "--- Smoke failure diagnostics ---" >&2
  echo "Check ............ ${label}" >&2
  echo "URL .............. ${url}" >&2
  echo "Curl exit ........ ${curl_exit}" >&2
  echo "HTTP status ...... ${actual_status}" >&2
  echo "Compose status ..." >&2
  docker compose ps --all >&2 || true
  echo "Gateway/Eureka/service logs (last 120 lines) ..." >&2
  docker compose logs --no-color --tail=120 \
    gateway discovery-service games-service user-service library-service \
    order-service payment-service >&2 || true
  echo "--- End smoke failure diagnostics ---" >&2
}

gateway_missing_services() {
  local health_file="$1"
  local expected_applications="${EXPECTED_EUREKA_APPLICATIONS[*]}"

  jq -r --arg expected "$expected_applications" '
    ($expected | split(" ")) as $expected_applications
    | .components.discoveryComposite.components.eureka.details.applications as $applications
    | if ($applications | type) != "object" then
        $expected_applications[]
      else
        $expected_applications[]
        | select(($applications[.] // 0) != 1)
      end
  ' "$health_file"
}

wait_for_gateway_service_discovery() {
  local attempt
  local health_file
  local http_status
  local curl_exit
  local missing_services

  health_file="$(mktemp)"
  echo "Waiting for Gateway's local Eureka registry at ${GATEWAY_DISCOVERY_HEALTH_URL}..."

  for attempt in $(seq 1 "$GATEWAY_DISCOVERY_WAIT_ATTEMPTS"); do
    curl_exit=0
    http_status="$(curl --silent --show-error \
      --output "$health_file" \
      --write-out '%{http_code}' \
      --connect-timeout 5 \
      --max-time 15 \
      "$GATEWAY_DISCOVERY_HEALTH_URL")" || curl_exit=$?

    if (( curl_exit != 0 )); then
      echo "Gateway discovery attempt ${attempt}/${GATEWAY_DISCOVERY_WAIT_ATTEMPTS}: transport failure (curl exit ${curl_exit}, HTTP ${http_status:-000})." >&2
    elif [[ "$http_status" != "200" ]]; then
      echo "Gateway discovery attempt ${attempt}/${GATEWAY_DISCOVERY_WAIT_ATTEMPTS}: expected HTTP 200, received HTTP ${http_status}." >&2
    elif ! jq -e '
      .status == "UP"
      and (.components.discoveryComposite.components.eureka.details.applications | type == "object")
    ' "$health_file" >/dev/null 2>&1; then
      echo "Gateway discovery attempt ${attempt}/${GATEWAY_DISCOVERY_WAIT_ATTEMPTS}: health response is not ready or has no Eureka applications map." >&2
    elif ! missing_services="$(gateway_missing_services "$health_file")"; then
      echo "Gateway discovery attempt ${attempt}/${GATEWAY_DISCOVERY_WAIT_ATTEMPTS}: unable to parse Eureka applications from health response." >&2
    elif [[ -z "$missing_services" ]]; then
      echo "Gateway local Eureka registry is ready; all expected services are visible."
      rm -f "$health_file"
      return 0
    else
      echo "Gateway discovery attempt ${attempt}/${GATEWAY_DISCOVERY_WAIT_ATTEMPTS}: services still absent: $(tr '\n' ' ' <<< "$missing_services")" >&2
    fi

    if (( attempt < GATEWAY_DISCOVERY_WAIT_ATTEMPTS )); then
      sleep "$GATEWAY_DISCOVERY_WAIT_INTERVAL_SECONDS"
    fi
  done

  echo "Gateway local Eureka registry did not converge after ${GATEWAY_DISCOVERY_WAIT_ATTEMPTS} attempts." >&2
  echo "Expected services: ${EXPECTED_EUREKA_APPLICATIONS[*]}" >&2
  echo "Gateway health endpoint: ${GATEWAY_DISCOVERY_HEALTH_URL}" >&2
  rm -f "$health_file"
  return 1
}

wait_for_application_stack() {
  local endpoint
  local eureka_apps
  local eureka_ready=0

  docker compose config -q
  docker compose up -d --no-build --wait --wait-timeout 300 \
    mongodb postgresql "${APP_SERVICES[@]}"

  for endpoint in \
    http://localhost:8888/actuator/health \
    http://localhost:8761/actuator/health \
    http://localhost:8222/actuator/health \
    http://localhost/; do
    curl --fail --retry 12 --retry-delay 5 --retry-connrefused "$endpoint"
  done

  for _ in $(seq 1 24); do
    if eureka_apps="$(curl --silent --show-error --fail --retry 3 --retry-delay 2 --retry-connrefused \
      -H 'Accept: application/json' http://localhost:8761/eureka/apps)"; then
      if validate_eureka_registrations "$eureka_apps"; then
        eureka_ready=1
        break
      fi
    else
      echo "Eureka registration check: request failed; retrying." >&2
    fi

    sleep 5
  done

  (( eureka_ready )) || {
    echo "Eureka did not converge to exactly one instance for every expected application within two minutes." >&2
    exit 1
  }

  wait_for_gateway_service_discovery
}

run_integration_smoke_checks() {
  local gateway_url="http://localhost:8222"

  assert_http_status "login endpoint is reachable" 401 \
    "${gateway_url}/api/v1/auth/login" \
    -X POST -H 'Content-Type: application/json' \
    --data '{"username":"__ci_nonexistent_user__","password":"__ci_nonexistent_password__"}'

  assert_http_status "public games catalogue" 200 \
    "${gateway_url}/api/v1/games"

  assert_http_status "frontend proxies the public games catalogue" 200 \
    "http://localhost/api/v1/games"

  assert_http_status "protected users route rejects an unauthenticated request" 401 \
    "${gateway_url}/api/v1/users/username/__ci_smoke_user__"

  assert_http_status "protected purchase route rejects an unauthenticated request" 401 \
    "${gateway_url}/api/v1/games/purchase" \
    -X POST -H 'Content-Type: application/json' --data '[]'

  assert_http_status "automatic Eureka route is not exposed" 404 \
    "${gateway_url}/GAMES-SERVICE/api/v1/games/purchase" \
    -X POST -H 'Content-Type: application/json' --data '[]'
}
