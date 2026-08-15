#!/usr/bin/env bash

set -euo pipefail

source "$(dirname "$0")/lib/application-images.sh"

readonly TRIVY_IMAGE="aquasec/trivy:0.73.0@sha256:4bbf3824d974b70f27631005e2e6194d4d8fbd6e72c4a9e04cf521e25c5cb07f"
readonly TRIVY_REPORT="reports/trivy-dependencies.json"
readonly MAVEN_REPOSITORY="${MAVEN_REPOSITORY:-${HOME}/.m2/repository}"

ensure_jq
mkdir -p reports .trivy-cache

ensure_resolved_maven_repository() {
  if [[ ! -d "$MAVEN_REPOSITORY" ]] || \
      [[ -z "$(find "$MAVEN_REPOSITORY" -type f -name '*.pom' -print -quit)" ]]; then
    echo "Resolved Maven POM workspace is missing; the SCA scan would be incomplete." >&2
    return 1
  fi
}

trivy() {
  docker run --rm \
    -v "$PWD:/workspace" \
    -w /workspace \
    -v "$MAVEN_REPOSITORY:/root/.m2/repository:ro" \
    -v "$PWD/.trivy-cache:/root/.cache/" \
    "$TRIVY_IMAGE" "$@"
}

validate_dependency_report() {
  [[ -s "$TRIVY_REPORT" ]] || {
    echo "Trivy did not create a dependency JSON report." >&2
    return 1
  }

  jq empty "$TRIVY_REPORT" >/dev/null 2>&1 || {
    echo "Trivy created an invalid dependency JSON report." >&2
    return 1
  }

  # backend-build-test stages its resolved Maven POM repository in the workflow
  # workspace. Fail explicitly if that transfer is absent or incomplete instead
  # of accepting a direct-only SCA report with a misleading zero-vulnerability result.
  jq -e '
    any(
      .Results[]?;
      .Type == "pom"
      and (.Target | test("^[^/]+/pom\\.xml$"))
      and any(.Packages[]?; .Relationship == "indirect")
    )
  ' "$TRIVY_REPORT" >/dev/null || {
    echo "Resolved Maven POM workspace is incomplete; no transitive backend dependencies were found." >&2
    return 1
  }
}

gate_high_or_critical_vulnerabilities() {
  jq -e '
    [
      .Results[]?.Vulnerabilities[]?
      | select(.Severity == "HIGH" or .Severity == "CRITICAL")
    ] | length == 0
  ' "$TRIVY_REPORT" >/dev/null || {
    echo "Trivy reported at least one HIGH or CRITICAL dependency vulnerability." >&2
    return 1
  }
}

ensure_resolved_maven_repository

# Keep every severity in the artifact; only the jq gate filters HIGH/CRITICAL.
# npm development dependencies are intentional supply-chain coverage because
# install hooks execute code during npm ci (163 findings versus 29 at adoption).
trivy fs \
  --scanners vuln \
  --include-dev-deps \
  --exit-code 0 \
  --format json \
  --output "$TRIVY_REPORT" \
  --offline-scan \
  --skip-dirs UI_Spring/node_modules \
  --skip-dirs reports \
  --no-progress \
  --skip-version-check \
  --timeout 20m \
  .

validate_dependency_report
gate_high_or_critical_vulnerabilities
