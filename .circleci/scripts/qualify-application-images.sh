#!/usr/bin/env bash

set -euo pipefail

readonly APP_SERVICES=(
  config-server discovery-service gateway games-service library-service
  order-service payment-service user-service client
)
readonly TRIVY_IMAGE="aquasec/trivy:0.73.0"
readonly ZAP_IMAGE="ghcr.io/zaproxy/zaproxy@sha256:781a2bdaea47324e7bab583e2263f21d257b0aee61ed51521a5be45f5f5081ef"

: "${CIRCLE_SHA1:?CIRCLE_SHA1 must be defined by CircleCI}"
export IMAGE_TAG="${CIRCLE_SHA1}"
export JWT_SECRET="$(openssl rand -base64 48)"
export COMPOSE_PROJECT_NAME="ci${CIRCLE_BUILD_NUM:?CIRCLE_BUILD_NUM must be defined by CircleCI}"

case "${PUBLISH_IMAGES:-false}" in
  false)
    export IMAGE_REPOSITORY_PREFIX="${IMAGE_REPOSITORY_PREFIX:-ci.local}"
    ;;
  true)
    : "${ACR_LOGIN_SERVER:?ACR_LOGIN_SERVER must be defined in the acr-publish CircleCI context}"
    : "${ACR_USERNAME:?ACR_USERNAME must be defined in the acr-publish CircleCI context}"
    : "${ACR_PASSWORD:?ACR_PASSWORD must be defined in the acr-publish CircleCI context}"
    export IMAGE_REPOSITORY_PREFIX="${ACR_LOGIN_SERVER}"
    ;;
  *)
    echo "PUBLISH_IMAGES must be either true or false." >&2
    exit 1
    ;;
esac

if ! command -v jq >/dev/null 2>&1; then
  sudo apt-get update
  sudo apt-get install -y jq
fi

mkdir -p reports/trivy-images reports/sbom reports/zap .trivy-cache

cleanup() {
  docker compose logs --no-color > reports/docker-compose.log || true
  docker compose down --volumes --remove-orphans || true
}
trap cleanup EXIT

docker compose config -q
docker compose build "${APP_SERVICES[@]}"

trivy() {
  docker run --rm \
    -v /var/run/docker.sock:/var/run/docker.sock \
    -v "$PWD/reports:/reports" \
    -v "$PWD/.trivy-cache:/root/.cache/" \
    "$TRIVY_IMAGE" "$@"
}

image_scan_failed=0
for service in "${APP_SERVICES[@]}"; do
  image="${IMAGE_REPOSITORY_PREFIX}/${service}:${IMAGE_TAG}"

  trivy image \
    --format cyclonedx \
    --output "/reports/sbom/${service}.cdx.json" \
    --no-progress \
    --skip-version-check \
    --timeout 20m \
    "$image"

  trivy image \
    --scanners vuln \
    --severity HIGH,CRITICAL \
    --exit-code 0 \
    --format json \
    --output "/reports/trivy-images/${service}.json" \
    --no-progress \
    --skip-version-check \
    --timeout 20m \
    "$image"

  if ! trivy image \
    --scanners vuln \
    --severity HIGH,CRITICAL \
    --exit-code 1 \
    --no-progress \
    --skip-version-check \
    --timeout 20m \
    "$image"; then
    image_scan_failed=1
  fi
done

if (( image_scan_failed )); then
  echo "At least one application image has HIGH or CRITICAL vulnerabilities." >&2
  exit 1
fi

docker compose up -d --no-build --wait --wait-timeout 300 \
  mongodb postgresql "${APP_SERVICES[@]}"

for endpoint in \
  http://localhost:8888/actuator/health \
  http://localhost:8761/actuator/health \
  http://localhost:8222/actuator/health \
  http://localhost/; do
  curl --fail --retry 12 --retry-delay 5 --retry-connrefused "$endpoint"
done

eureka_ready=0
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

zap_baseline() {
  local target_name="$1"
  local target_url="$2"

  docker run --rm \
    --network "${COMPOSE_PROJECT_NAME}_microservices" \
    -v "$PWD/reports/zap:/zap/wrk" \
    "$ZAP_IMAGE" \
    zap-baseline.py \
    -t "$target_url" \
    -m 2 \
    -I \
    --autooff \
    -J "/zap/wrk/${target_name}.json" \
    -r "/zap/wrk/${target_name}.html"

  jq -e '
    [ .site[]?.alerts[]? | select((.riskcode // "0" | tonumber) >= 3) ] | length == 0
  ' "reports/zap/${target_name}.json" >/dev/null || {
    echo "ZAP reported at least one HIGH-risk alert for ${target_name}." >&2
    exit 1
  }
}

zap_baseline client http://client:8080/
zap_baseline gateway http://gateway:8222/actuator/health

if [[ "${PUBLISH_IMAGES:-false}" == "true" ]]; then
  echo "$ACR_PASSWORD" | docker login "$ACR_LOGIN_SERVER" \
    --username "$ACR_USERNAME" \
    --password-stdin

  docker compose push "${APP_SERVICES[@]}"

  : > reports/acr-image-manifest.txt
  for service in "${APP_SERVICES[@]}"; do
    printf '%s\n' "${IMAGE_REPOSITORY_PREFIX}/${service}:${IMAGE_TAG}" \
      >> reports/acr-image-manifest.txt
  done
fi
