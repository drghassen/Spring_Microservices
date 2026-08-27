#!/usr/bin/env bash

set -euo pipefail

# shellcheck source-path=SCRIPTDIR
# shellcheck source=lib/application-images.sh
source "$(dirname "$0")/lib/application-images.sh"

readonly DATABASE_MIGRATIONS_SERVICE="database-migrations"
readonly DATABASE_MIGRATIONS_DOCKERFILE="database-migrations/Dockerfile"
readonly DATABASE_MIGRATIONS_CONTEXT="database-migrations"
readonly ARCHIVE_DIRECTORY="ci-database-migrations"
readonly ARCHIVE_PATH="${ARCHIVE_DIRECTORY}/database-migrations-image.tar.zst"
readonly SBOM_FILE="reports/sbom-reports/${DATABASE_MIGRATIONS_SERVICE}/${DATABASE_MIGRATIONS_SERVICE}-${IMAGE_TAG}.cdx.json"
readonly TRIVY_IMAGE="aquasec/trivy:0.73.0@sha256:4bbf3824d974b70f27631005e2e6194d4d8fbd6e72c4a9e04cf521e25c5cb07f"
readonly SYFT_IMAGE="anchore/syft:v1.50.0@sha256:1288ea4c8b38767b4e620c1e312c8cb26b6e887a99b4f07ab6cd19fc6f225026"
readonly TRIVY_DB_PRIMARY_REPOSITORY="public.ecr.aws/aquasecurity/trivy-db:2"
readonly TRIVY_DB_FALLBACK_REPOSITORY="ghcr.io/aquasecurity/trivy-db:2"
readonly TRIVY_JAVA_DB_PRIMARY_REPOSITORY="public.ecr.aws/aquasecurity/trivy-java-db:1"
readonly TRIVY_JAVA_DB_FALLBACK_REPOSITORY="ghcr.io/aquasecurity/trivy-java-db:1"
readonly TRIVY_DOWNLOAD_TIMEOUT="45m"

configure_candidate_images
ensure_jq
ensure_zstd

readonly candidate_image="${IMAGE_REPOSITORY_PREFIX}/${DATABASE_MIGRATIONS_SERVICE}:${IMAGE_TAG}"
readonly trivy_report="reports/trivy-images/${DATABASE_MIGRATIONS_SERVICE}.json"

trivy() {
  docker run --rm \
    -e GODEBUG=http2client=0 \
    -v /var/run/docker.sock:/var/run/docker.sock \
    -v "$PWD/reports:/reports" \
    -v "$PWD/.trivy-cache:/root/.cache/" \
    "$TRIVY_IMAGE" "$@"
}

syft() {
  docker run --rm \
    -e SYFT_CHECK_FOR_APP_UPDATE=false \
    -v /var/run/docker.sock:/var/run/docker.sock \
    -v "$PWD/reports:/reports" \
    "$SYFT_IMAGE" "$@"
}

docker build \
  --file "$DATABASE_MIGRATIONS_DOCKERFILE" \
  --tag "$candidate_image" \
  "$DATABASE_MIGRATIONS_CONTEXT"

mkdir -p reports/trivy-images .trivy-cache "$(dirname "$SBOM_FILE")" "$ARCHIVE_DIRECTORY"

# Download both indexes independently so a slow registry cannot make the image
# scan appear stalled. The cache is reused without network access below.
trivy image \
  --download-db-only \
  --db-repository "$TRIVY_DB_PRIMARY_REPOSITORY" \
  --db-repository "$TRIVY_DB_FALLBACK_REPOSITORY" \
  --no-progress \
  --skip-version-check \
  --timeout "$TRIVY_DOWNLOAD_TIMEOUT"

trivy image \
  --download-java-db-only \
  --java-db-repository "$TRIVY_JAVA_DB_PRIMARY_REPOSITORY" \
  --java-db-repository "$TRIVY_JAVA_DB_FALLBACK_REPOSITORY" \
  --no-progress \
  --skip-version-check \
  --timeout "$TRIVY_DOWNLOAD_TIMEOUT"

trivy image \
  --scanners vuln \
  --severity HIGH,CRITICAL \
  --exit-code 0 \
  --format json \
  --output "/reports/trivy-images/${DATABASE_MIGRATIONS_SERVICE}.json" \
  --no-progress \
  --skip-db-update \
  --skip-java-db-update \
  --skip-version-check \
  --timeout "$TRIVY_DOWNLOAD_TIMEOUT" \
  "$candidate_image"

[[ -s "$trivy_report" ]] || {
  echo "Trivy did not create a database-migrations JSON report." >&2
  exit 1
}

jq empty "$trivy_report" >/dev/null
jq -e '
  [
    .Results[]?.Vulnerabilities[]?
    | select(.Severity == "HIGH" or .Severity == "CRITICAL")
  ] | length == 0
' "$trivy_report" >/dev/null || {
  echo "Trivy reported at least one HIGH or CRITICAL vulnerability for database-migrations." >&2
  exit 1
}

docker pull "$SYFT_IMAGE" >/dev/null
syft "$candidate_image" \
  -o "cyclonedx-json@1.6=/reports/${SBOM_FILE#reports/}"

[[ -s "$SBOM_FILE" ]] || {
  echo "Syft did not create a database-migrations SBOM." >&2
  exit 1
}

jq -e '.bomFormat == "CycloneDX" and .specVersion == "1.6"' "$SBOM_FILE" >/dev/null

docker image save "$candidate_image" | zstd --threads=0 --fast --quiet -o "$ARCHIVE_PATH"
sha256sum "$ARCHIVE_PATH" > "${ARCHIVE_PATH}.sha256"
printf '%s\n' "$candidate_image" > "${ARCHIVE_DIRECTORY}/image-manifest.txt"
