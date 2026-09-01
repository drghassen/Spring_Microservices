#!/usr/bin/env bash

set -euo pipefail
umask 077

(($# == 0)) || {
  echo "CircleCI workspace preparation does not accept a custom path." >&2
  exit 1
}

repository_root="$(git rev-parse --show-toplevel 2>/dev/null)" || {
  echo "Unable to resolve the repository root for CircleCI workspace preparation." >&2
  exit 1
}
repository_root="$(cd "$repository_root" && pwd -P)"
readonly repository_root
working_directory="$(pwd -P)"
readonly working_directory
workspace_root="${repository_root}/.circleci-workspace"
readonly workspace_root

[[ "$repository_root" != / && "$working_directory" == "$repository_root" && \
  "$workspace_root" == "${working_directory}/.circleci-workspace" ]] || {
  echo "Unexpected CircleCI workspace path." >&2
  exit 1
}

if [[ -L "$workspace_root" ]]; then
  echo "Refusing to remove a symlinked CircleCI workspace directory." >&2
  exit 1
fi

if [[ -e "$workspace_root" ]]; then
  [[ -d "$workspace_root" ]] || {
    echo "CircleCI workspace path exists but is not a directory." >&2
    exit 1
  }

  echo "Removing stale local CircleCI workspace from a previous execution."
  rm -rf -- "$workspace_root"
fi

mkdir -p -- "$workspace_root"
