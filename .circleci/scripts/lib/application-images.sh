#!/usr/bin/env bash

set -euo pipefail

readonly APP_SERVICES=(
  config-server discovery-service gateway games-service library-service
  order-service payment-service user-service client
)

configure_candidate_images() {
  : "${CIRCLE_SHA1:?CIRCLE_SHA1 must be defined by CircleCI}"
  : "${CIRCLE_WORKFLOW_ID:?CIRCLE_WORKFLOW_ID must be defined by CircleCI}"

  export IMAGE_TAG="${CIRCLE_SHA1}-${CIRCLE_WORKFLOW_ID}"
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

configure_runtime_environment() {
  : "${CIRCLE_BUILD_NUM:?CIRCLE_BUILD_NUM must be defined by CircleCI}"

  export JWT_SECRET="$(openssl rand -base64 48)"
  export COMPOSE_PROJECT_NAME="ci${CIRCLE_BUILD_NUM}"
}

collect_compose_logs_and_cleanup() {
  local report_name="${COMPOSE_REPORT_NAME:-docker-compose}"

  mkdir -p reports
  docker compose logs --no-color > "reports/${report_name}.log" || true
  docker compose down --volumes --remove-orphans || true
}

wait_for_application_stack() {
  local endpoint
  local eureka_apps
  local registrations_valid
  local application
  local instance_count
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
    eureka_apps="$(curl --fail --retry 3 --retry-delay 2 --retry-connrefused \
      -H 'Accept: application/json' http://localhost:8761/eureka/apps)"
    registrations_valid=1

    for application in \
      GAMES-SERVICE GATEWAY LIBRARY-SERVICE ORDER-SERVICE PAYMENT-SERVICE USER-SERVICE; do
      instance_count="$(printf '%s' "$eureka_apps" | jq -r --arg application "$application" '
        .applications.application[]
        | select(.name == $application)
        | if (.instance | type) == "array" then (.instance | length) else 1 end
      ')"
      if [[ "$instance_count" != "1" ]]; then
        registrations_valid=0
        break
      fi
    done

    if (( registrations_valid )); then
      eureka_ready=1
      break
    fi
    sleep 5
  done

  (( eureka_ready )) || {
    echo "Eureka did not converge to one instance per application within two minutes." >&2
    exit 1
  }
}
