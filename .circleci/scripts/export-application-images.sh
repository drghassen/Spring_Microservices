#!/usr/bin/env bash

set -euo pipefail

source "$(dirname "$0")/lib/application-images.sh"
# shellcheck source=lib/report-evidence.sh
source "$(dirname "$0")/lib/report-evidence.sh"

readonly archive_group="${1:?Usage: $0 <frontend|backend> <service> [<service> ...]}"
shift

(( $# > 0 )) || {
  echo "At least one service must be supplied for image export." >&2
  exit 2
}

configure_candidate_images
ensure_zstd

readonly archive_directory="ci-image-archives/${archive_group}"
readonly archive_path="${archive_directory}/application-images.tar.zst"

mapfile -t image_references < <(candidate_image_references "$@")

report_header "DEVSECOPS PIPELINE - CONTAINER IMAGE EXPORT"
report_pipeline_context
report_field "Archive group" "$archive_group"
report_field "Candidate tag" "$IMAGE_TAG"
report_field "Images" "${#image_references[@]}"
report_field "Archive" "$archive_path"
report_footer

docker image inspect "${image_references[@]}" >/dev/null

mkdir -p "$archive_directory"
docker image save "${image_references[@]}" | zstd --threads=0 --fast --quiet -o "$archive_path"
sha256sum "$archive_path" > "${archive_path}.sha256"

printf '%s\n' "${image_references[@]}" > "${archive_directory}/image-manifest.txt"

report_header "CONTAINER IMAGE EXPORT SUMMARY"
report_field "Images exported" "${#image_references[@]}"
report_field "Checksum" "GENERATED"
report_field "Archive" "$archive_path"
report_field "RESULT" "IMAGE EXPORT PASSED"
report_footer
