#!/usr/bin/env bash

set -euo pipefail

source "$(dirname "$0")/lib/application-images.sh"

readonly archive_root="ci-image-archives"

configure_candidate_images
ensure_zstd

shopt -s nullglob
archives=("${archive_root}"/*/application-images.tar.zst)
(( ${#archives[@]} == 2 )) || {
  echo "Expected exactly frontend and backend image archives in ${archive_root}." >&2
  exit 1
}

for archive_path in "${archives[@]}"; do
  sha256sum --check "${archive_path}.sha256"
  zstd --decompress --stdout --quiet "$archive_path" | docker image load
done

mapfile -t image_references < <(candidate_image_references)
docker image inspect "${image_references[@]}" >/dev/null
