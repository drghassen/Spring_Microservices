#!/usr/bin/env bash

set -euo pipefail

source "$(dirname "$0")/lib/application-images.sh"
# shellcheck source=lib/report-evidence.sh
source "$(dirname "$0")/lib/report-evidence.sh"

readonly DATABASE_MIGRATIONS_SERVICE="database-migrations"
readonly ARCHIVE_DIRECTORY="ci-database-migrations"
readonly ARCHIVE_PATH="${ARCHIVE_DIRECTORY}/database-migrations-image.tar.zst"

configure_candidate_images
ensure_zstd

readonly candidate_image="${IMAGE_REPOSITORY_PREFIX}/${DATABASE_MIGRATIONS_SERVICE}:${IMAGE_TAG}"

report_header "DEVSECOPS PIPELINE - DATABASE MIGRATION IMAGE LOADING"
report_pipeline_context
report_field "Image" "$candidate_image"
report_field "Archive" "$ARCHIVE_PATH"
report_footer

[[ -s "$ARCHIVE_PATH" && -s "${ARCHIVE_PATH}.sha256" && -s "${ARCHIVE_DIRECTORY}/image-manifest.txt" ]] || {
  echo "database-migrations workspace archive is incomplete." >&2
  exit 1
}

sha256sum --check "${ARCHIVE_PATH}.sha256"
grep --fixed-strings --line-regexp --quiet "$candidate_image" "${ARCHIVE_DIRECTORY}/image-manifest.txt" || {
  echo "database-migrations archive manifest does not contain the candidate image." >&2
  exit 1
}

zstd --decompress --stdout --quiet "$ARCHIVE_PATH" | docker image load
docker image inspect "$candidate_image" >/dev/null

report_header "DATABASE MIGRATION IMAGE SUMMARY"
report_field "Checksum" "PASSED"
report_field "Manifest" "PASSED"
report_field "Image loading" "PASSED"
report_field "RESULT" "DATABASE MIGRATION IMAGE READY"
report_footer
