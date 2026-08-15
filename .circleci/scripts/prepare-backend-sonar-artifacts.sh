#!/usr/bin/env bash

set -euo pipefail

readonly ARTIFACT_DIRECTORY="ci-backend-sonar"

usage() {
  echo "Usage: $0 {stage|restore}" >&2
  exit 2
}

stage_artifacts() {
  local module
  local module_name
  local target_directory

  rm -rf "$ARTIFACT_DIRECTORY"
  mkdir -p "$ARTIFACT_DIRECTORY"

  while IFS= read -r module; do
    module_name="${module#./}"
    target_directory="$module/target"

    [[ -d "$target_directory/classes" ]] || {
      echo "Compiled backend classes are missing for ${module_name}." >&2
      exit 1
    }

    mkdir -p "$ARTIFACT_DIRECTORY/$module_name"
    cp -a "$target_directory/classes" "$ARTIFACT_DIRECTORY/$module_name/classes"

    if [[ -f "$target_directory/site/jacoco/jacoco.xml" ]]; then
      mkdir -p "$ARTIFACT_DIRECTORY/$module_name/jacoco"
      cp "$target_directory/site/jacoco/jacoco.xml" \
        "$ARTIFACT_DIRECTORY/$module_name/jacoco/jacoco.xml"
    fi
  done < <(find . -mindepth 2 -maxdepth 2 -name pom.xml -printf '%h\n' | LC_ALL=C sort)
}

restore_artifacts() {
  local staged_module
  local module_name
  local target_directory

  [[ -d "$ARTIFACT_DIRECTORY" ]] || {
    echo "Backend SonarQube workspace is missing: ${ARTIFACT_DIRECTORY}." >&2
    exit 1
  }

  shopt -s nullglob
  for staged_module in "$ARTIFACT_DIRECTORY"/*; do
    module_name="$(basename "$staged_module")"
    target_directory="$module_name/target"

    [[ -d "$staged_module/classes" ]] || {
      echo "Staged classes are missing for ${module_name}." >&2
      exit 1
    }

    mkdir -p "$target_directory/classes"
    cp -a "$staged_module/classes/." "$target_directory/classes/"

    if [[ -f "$staged_module/jacoco/jacoco.xml" ]]; then
      mkdir -p "$target_directory/site/jacoco"
      cp "$staged_module/jacoco/jacoco.xml" "$target_directory/site/jacoco/jacoco.xml"
    fi
  done
}

case "${1:-}" in
  stage)
    stage_artifacts
    ;;
  restore)
    restore_artifacts
    ;;
  *)
    usage
    ;;
esac
