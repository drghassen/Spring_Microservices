#!/usr/bin/env bash

set -euo pipefail

source "$(dirname "$0")/lib/application-images.sh"
# shellcheck source=lib/report-evidence.sh
source "$(dirname "$0")/lib/report-evidence.sh"

readonly archive_root="ci-image-archives"

configure_candidate_images
ensure_zstd

shopt -s nullglob
archives=("${archive_root}"/*/application-images.tar.zst)
(( ${#archives[@]} == 2 )) || {
  echo "Expected exactly frontend and backend image archives in ${archive_root}." >&2
  exit 1
}

report_header "DEVSECOPS PIPELINE - CANDIDATE IMAGE LOADING"
report_pipeline_context
report_field "Candidate tag" "$IMAGE_TAG"
report_field "Archives expected" "2"
report_field "Archives found" "${#archives[@]}"
report_footer

for archive_path in "${archives[@]}"; do
  printf '[INFO] Verifying and loading: %s\n' "$archive_path"
  sha256sum --check "${archive_path}.sha256"
  zstd --decompress --stdout --quiet "$archive_path" | docker image load
done

mapfile -t image_references < <(candidate_image_references)
docker image inspect "${image_references[@]}" >/dev/null

report_header "CANDIDATE IMAGE LOADING SUMMARY"
report_field "Archives loaded" "${#archives[@]}"
report_field "Images available" "${#image_references[@]}"
report_field "Integrity checks" "PASSED"
report_field "RESULT" "CANDIDATE IMAGES READY"
report_footer
