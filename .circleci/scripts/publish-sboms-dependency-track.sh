#!/usr/bin/env bash

set -Eeuo pipefail

source "$(dirname "$0")/lib/application-images.sh"

readonly SYFT_VERSION="1.50.0"
readonly SYFT_IMAGE="anchore/syft:v${SYFT_VERSION}@sha256:1288ea4c8b38767b4e620c1e312c8cb26b6e887a99b4f07ab6cd19fc6f225026"
readonly SBOM_REPORT_ROOT="reports/sbom-reports"
readonly DTRACK_REPORT_ROOT="reports/dependency-track"
readonly DTRACK_WAIT_ATTEMPTS="${DTRACK_WAIT_ATTEMPTS:-30}"
readonly DTRACK_WAIT_INTERVAL_SECONDS="${DTRACK_WAIT_INTERVAL_SECONDS:-5}"
readonly DTRACK_PARALLELISM="${DTRACK_PARALLELISM:-3}"

: "${DTRACK_URL:?DTRACK_URL must be defined in the dependency-track CircleCI context}"
: "${DTRACK_API_KEY:?DTRACK_API_KEY must be defined in the dependency-track CircleCI context}"
: "${DTRACK_PARENT_UUID:?DTRACK_PARENT_UUID must be defined in the dependency-track CircleCI context}"

configure_candidate_images
ensure_jq

readonly DTRACK_API_BASE="${DTRACK_URL%/}"

error_for_service() {
  local service="$1"
  local message="$2"

  printf 'ERROR [%s]: %s\n' "$service" "$message" >&2
}

validate_parallelism() {
  [[ "$DTRACK_PARALLELISM" =~ ^[1-4]$ ]] || {
    echo "DTRACK_PARALLELISM must be an integer from 1 to 4; got: ${DTRACK_PARALLELISM}" >&2
    exit 1
  }
}

dtrack_get() {
  local path="$1"

  curl --silent --show-error --fail \
    -H "X-Api-Key: ${DTRACK_API_KEY}" \
    "${DTRACK_API_BASE}${path}"
}

wait_for_dependency_track() {
  local attempt
  local health_file
  local version_file
  local health_status
  local version_status

  health_file="$(mktemp)"
  version_file="$(mktemp)"

  echo "Waiting for Dependency-Track API at ${DTRACK_API_BASE}..."
  for attempt in $(seq 1 "$DTRACK_WAIT_ATTEMPTS"); do
    printf 'Attempt %s/%s...\n' "$attempt" "$DTRACK_WAIT_ATTEMPTS"

    health_status="$(curl --silent --show-error --output "$health_file" --write-out '%{http_code}' \
      "${DTRACK_API_BASE}/health/ready" || true)"
    if [[ "$health_status" == "200" ]] && jq -e '.status == "UP"' "$health_file" >/dev/null 2>&1; then
      echo "Dependency-Track readiness endpoint is UP."
      rm -f "$health_file" "$version_file"
      return 0
    fi

    version_status="$(curl --silent --show-error --output "$version_file" --write-out '%{http_code}' \
      "${DTRACK_API_BASE}/api/version" || true)"
    if [[ "$version_status" == "200" ]] && jq empty "$version_file" >/dev/null 2>&1; then
      echo "Dependency-Track version endpoint is reachable."
      rm -f "$health_file" "$version_file"
      return 0
    fi

    sleep "$DTRACK_WAIT_INTERVAL_SECONDS"
  done

  rm -f "$health_file" "$version_file"
  echo "Dependency-Track API did not become reachable before timeout." >&2
  exit 1
}

dependency_track_version() {
  curl --silent --show-error --fail "${DTRACK_API_BASE}/api/version" \
    | jq -r '.version // .applicationVersion // "unknown"'
}

validate_parent_project() {
  local parent_file
  local parent_name

  [[ "$DTRACK_PARENT_UUID" =~ ^[0-9a-fA-F-]{36}$ ]] || {
    echo "DTRACK_PARENT_UUID must be a UUID; got: ${DTRACK_PARENT_UUID}" >&2
    exit 1
  }

  parent_file="$(mktemp)"
  if ! dtrack_get "/api/v1/project/${DTRACK_PARENT_UUID}" > "$parent_file"; then
    rm -f "$parent_file"
    echo "Dependency-Track parent project lookup failed. Verify DTRACK_PARENT_UUID and API key permissions." >&2
    exit 1
  fi

  parent_name="$(jq -r '.name // empty' "$parent_file")"
  [[ -n "$parent_name" ]] || {
    rm -f "$parent_file"
    echo "Dependency-Track parent project response did not include a project name." >&2
    exit 1
  }

  printf '[Dependency-Track]\n'
  printf 'API ............... READY\n'
  printf 'Version ........... %s\n' "$(dependency_track_version)"
  printf 'Parent ............ %s\n' "$parent_name"
  printf 'Parent UUID ....... %s\n' "$DTRACK_PARENT_UUID"

  rm -f "$parent_file"
}

syft() {
  docker run --rm \
    -v /var/run/docker.sock:/var/run/docker.sock \
    -v "$PWD/reports:/reports" \
    "$SYFT_IMAGE" "$@"
}

prepare_syft() {
  docker pull "$SYFT_IMAGE" >/dev/null
  syft version
}

sbom_file_for_service() {
  local service="$1"

  printf '%s/%s/%s-%s.cdx.json\n' "$SBOM_REPORT_ROOT" "$service" "$service" "$IMAGE_TAG"
}

generate_sbom() {
  local service="$1"
  local image="$2"
  local sbom_file="$3"

  docker image inspect "$image" >/dev/null || {
    error_for_service "$service" "candidate image is missing: ${image}"
    return 1
  }

  mkdir -p "$(dirname "$sbom_file")"
  syft "$image" \
    -o "cyclonedx-json@1.6=/reports/${sbom_file#reports/}"

  [[ -s "$sbom_file" ]] || {
    error_for_service "$service" "Syft did not create a non-empty SBOM: ${sbom_file}"
    return 1
  }
}

validate_sbom() {
  local service="$1"
  local image="$2"
  local sbom_file="$3"
  local bom_format
  local spec_version
  local components
  local dependencies

  jq empty "$sbom_file" >/dev/null || {
    error_for_service "$service" "SBOM is not valid JSON: ${sbom_file}"
    return 1
  }

  bom_format="$(jq -r '.bomFormat // empty' "$sbom_file")"
  spec_version="$(jq -r '.specVersion // empty' "$sbom_file")"
  [[ "$bom_format" == "CycloneDX" ]] || {
    error_for_service "$service" "SBOM bomFormat must be CycloneDX, got: ${bom_format:-<missing>}"
    return 1
  }
  [[ "$spec_version" == "1.6" ]] || {
    error_for_service "$service" "SBOM specVersion must be 1.6, got: ${spec_version:-<missing>}"
    return 1
  }

  jq -e '
    .bomFormat == "CycloneDX"
    and .specVersion == "1.6"
  ' "$sbom_file" >/dev/null

  components="$(jq -r '(.components // []) | length' "$sbom_file")"
  dependencies="$(jq -r '(.dependencies // []) | length' "$sbom_file")"

  printf '\n[SBOM %s]\n' "$service"
  printf 'Image ............. %s\n' "$image"
  printf 'File .............. %s\n' "$sbom_file"
  printf 'Format ............ %s\n' "$bom_format"
  printf 'Spec .............. %s\n' "$spec_version"
  printf 'Components ........ %s\n' "$components"
  printf 'Dependencies ...... %s\n' "$dependencies"
  jq '{
    bomFormat,
    specVersion,
    components: ((.components // []) | length),
    dependencies: ((.dependencies // []) | length)
  }' "$sbom_file"
}

upload_sbom() {
  local service="$1"
  local sbom_file="$2"
  local response_file="$3"
  local http_status

  http_status="$(curl --silent --show-error \
    --output "$response_file" \
    --write-out '%{http_code}' \
    --request POST "${DTRACK_API_BASE}/api/v1/bom" \
    -H "X-Api-Key: ${DTRACK_API_KEY}" \
    -F "autoCreate=true" \
    -F "projectName=${service}" \
    -F "projectVersion=${IMAGE_TAG}" \
    -F "parentUUID=${DTRACK_PARENT_UUID}" \
    -F "isLatest=true" \
    -F "bom=@${sbom_file};type=application/json")"

  [[ "$http_status" =~ ^2[0-9][0-9]$ ]] || {
    error_for_service "$service" "Dependency-Track rejected SBOM with HTTP ${http_status}"
    return 1
  }

  jq empty "$response_file" >/dev/null || {
    error_for_service "$service" "Dependency-Track response is not valid JSON"
    return 1
  }

  jq -e '.token | type == "string" and length > 0' "$response_file" >/dev/null || {
    error_for_service "$service" "Dependency-Track response did not include a BOM processing token"
    return 1
  }

  printf 'Upload ............ ACCEPTED\n'
}

record_upload_summary() {
  local service="$1"
  local image="$2"
  local sbom_file="$3"
  local summary_file="$4"

  jq -n \
    --arg service "$service" \
    --arg image "$image" \
    --arg imageTag "$IMAGE_TAG" \
    --arg sbom "$sbom_file" \
    --arg parentUUID "$DTRACK_PARENT_UUID" \
    '{
      service: $service,
      image: $image,
      imageTag: $imageTag,
      sbom: $sbom,
      parentUUID: $parentUUID,
      autoCreate: true,
      isLatest: true,
      uploadAccepted: true,
      tokenReturned: true
    }' > "$summary_file"
}

publish_service_sbom() {
  local service="$1"
  local image
  local sbom_file
  local service_report_dir
  local response_file
  local summary_file

  image="${IMAGE_REPOSITORY_PREFIX}/${service}:${IMAGE_TAG}"
  sbom_file="$(sbom_file_for_service "$service")"
  service_report_dir="${DTRACK_REPORT_ROOT}/${service}"
  response_file="${service_report_dir}/upload-response.json"
  summary_file="${service_report_dir}/upload-summary.json"

  mkdir -p "$service_report_dir"
  rm -f -- "$response_file" "$summary_file"

  generate_sbom "$service" "$image" "$sbom_file"
  validate_sbom "$service" "$image" "$sbom_file"
  upload_sbom "$service" "$sbom_file" "$response_file"
  record_upload_summary "$service" "$image" "$sbom_file" "$summary_file"
}

wait_for_publish_batch() {
  local batch_failed=0
  local index
  local pid
  local service

  for index in "${!publish_pids[@]}"; do
    pid="${publish_pids[$index]}"
    service="${publish_services[$index]}"
    if wait "$pid"; then
      printf 'Dependency-Track SBOM publication completed for %s.\n' "$service"
    else
      error_for_service "$service" "SBOM generation or Dependency-Track upload failed"
      batch_failed=1
    fi
  done

  publish_pids=()
  publish_services=()
  return "$batch_failed"
}

cleanup_publish_jobs() {
  local pid

  for pid in "${publish_pids[@]:-}"; do
    [[ -n "$pid" ]] || continue
    if kill -0 "$pid" 2>/dev/null; then
      kill "$pid" 2>/dev/null || true
      wait "$pid" 2>/dev/null || true
    fi
  done

  publish_pids=()
  publish_services=()
}

merge_upload_summaries() {
  local service
  local summary_file
  local aggregate_summary="${DTRACK_REPORT_ROOT}/upload-summary.jsonl"

  : > "$aggregate_summary"
  for service in "${APP_SERVICES[@]}"; do
    summary_file="${DTRACK_REPORT_ROOT}/${service}/upload-summary.json"
    [[ -s "$summary_file" ]] || {
      error_for_service "$service" "missing per-service upload summary: ${summary_file}"
      return 1
    }
    jq -c . "$summary_file" >> "$aggregate_summary"
  done
}

mkdir -p "$SBOM_REPORT_ROOT" "$DTRACK_REPORT_ROOT"
: > "${DTRACK_REPORT_ROOT}/upload-summary.jsonl"

validate_parallelism
wait_for_dependency_track
validate_parent_project
prepare_syft

declare -a publish_pids=()
declare -a publish_services=()
publish_failed=0
trap cleanup_publish_jobs EXIT

for service in "${APP_SERVICES[@]}"; do
  publish_service_sbom "$service" &
  publish_pids+=("$!")
  publish_services+=("$service")

  if (( ${#publish_pids[@]} >= DTRACK_PARALLELISM )); then
    wait_for_publish_batch || publish_failed=1
  fi
done

if (( ${#publish_pids[@]} > 0 )); then
  wait_for_publish_batch || publish_failed=1
fi

if (( publish_failed )); then
  echo "One or more Dependency-Track SBOM publications failed." >&2
  exit 1
fi

merge_upload_summaries
