#!/usr/bin/env bash

set -euo pipefail

: "${SONAR_HOST_URL:?SONAR_HOST_URL must be defined in the sonarqube CircleCI context}"
: "${SONAR_FRONTEND_TOKEN:?SONAR_FRONTEND_TOKEN must be defined in the sonarqube CircleCI context}"

# Keep SonarScanner's standard environment-variable contract while giving each
# SonarQube project a narrowly scoped credential in CircleCI.
export SONAR_TOKEN="$SONAR_FRONTEND_TOKEN"

readonly COVERAGE_REPORT="ci-frontend-sonar/lcov.info"
readonly SONAR_SCANNER_VERSION="8.1.0.6389"
readonly SONAR_SCANNER_SHA256="bb8f709f9cb73352f8d1260a3b3c506c0f41146754bc630762c126d795499d0b"
readonly SONAR_SCANNER_ARCHIVE_URL="https://binaries.sonarsource.com/Distribution/sonar-scanner-cli/sonar-scanner-cli-${SONAR_SCANNER_VERSION}-linux-x64.zip"
readonly SONAR_SCANNER_HOME="${HOME}/.cache/sonar-scanner-cli/${SONAR_SCANNER_VERSION}"

[[ -f "$COVERAGE_REPORT" ]] || {
  echo "Frontend coverage report not found: $COVERAGE_REPORT" >&2
  exit 1
}

install_scanner() {
  local download_directory
  local archive

  if [[ -x "$SONAR_SCANNER_HOME/bin/sonar-scanner" ]]; then
    return
  fi

  command -v curl >/dev/null 2>&1 || {
    echo "curl is required to install SonarScanner CLI." >&2
    exit 1
  }
  command -v sha256sum >/dev/null 2>&1 || {
    echo "sha256sum is required to verify SonarScanner CLI." >&2
    exit 1
  }
  command -v unzip >/dev/null 2>&1 || {
    echo "unzip is required to install SonarScanner CLI." >&2
    exit 1
  }

  [[ ! -e "$SONAR_SCANNER_HOME" ]] || {
    echo "Incomplete SonarScanner installation at $SONAR_SCANNER_HOME." >&2
    exit 1
  }

  download_directory="$(mktemp -d)"
  archive="$download_directory/sonar-scanner.zip"

  curl --fail --silent --show-error --location \
    --retry 3 --retry-all-errors \
    "$SONAR_SCANNER_ARCHIVE_URL" \
    --output "$archive"
  printf '%s  %s\n' "$SONAR_SCANNER_SHA256" "$archive" | sha256sum --check --status

  unzip -q "$archive" -d "$download_directory"
  install -d "$(dirname "$SONAR_SCANNER_HOME")"
  mv "$download_directory/sonar-scanner-${SONAR_SCANNER_VERSION}-linux-x64" "$SONAR_SCANNER_HOME"
  rm -rf "$download_directory"
}

install_scanner

"$SONAR_SCANNER_HOME/bin/sonar-scanner" \
  -Dsonar.projectKey=Internship-Proxym-frontend \
  -Dsonar.projectName='Internship Proxym Frontend' \
  -Dsonar.projectBaseDir=UI_Spring \
  -Dsonar.sources=src \
  -Dsonar.tests=src \
  -Dsonar.exclusions='**/*.spec.ts' \
  -Dsonar.test.inclusions='**/*.spec.ts' \
  -Dsonar.javascript.lcov.reportPaths="../$COVERAGE_REPORT" \
  -Dsonar.typescript.tsconfigPaths=tsconfig.sonar.json \
  -Dsonar.scm.disabled=true \
  -Dsonar.qualitygate.wait=true \
  -Dsonar.qualitygate.timeout=300
