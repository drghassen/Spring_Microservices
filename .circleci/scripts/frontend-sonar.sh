#!/usr/bin/env bash

set -euo pipefail

: "${SONAR_HOST_URL:?SONAR_HOST_URL must be defined in the sonarqube CircleCI context}"
: "${SONAR_FRONTEND_TOKEN:?SONAR_FRONTEND_TOKEN must be defined in the sonarqube CircleCI context}"

# Keep SonarScanner's standard environment-variable contract while giving each
# SonarQube project a narrowly scoped credential in CircleCI.
export SONAR_TOKEN="$SONAR_FRONTEND_TOKEN"

readonly SONAR_SCANNER_IMAGE="sonarsource/sonar-scanner-cli@sha256:02372948eaeeb10dfbe0cfd4174d44b8e405d0aeae431532b2bdb21d0347bf23"
readonly COVERAGE_REPORT="UI_Spring/coverage/ui-spring/lcov.info"

[[ -f "$COVERAGE_REPORT" ]] || {
  echo "Frontend coverage report not found: $COVERAGE_REPORT" >&2
  exit 1
}

docker run --rm --network host \
  -e SONAR_HOST_URL \
  -e SONAR_TOKEN \
  -v "$PWD:/usr/src" \
  -w /usr/src \
  "$SONAR_SCANNER_IMAGE" \
  -Dsonar.projectKey=Internship-Proxym-frontend \
  -Dsonar.projectName='Internship Proxym Frontend' \
  -Dsonar.sources=UI_Spring/src \
  -Dsonar.tests=UI_Spring/src \
  -Dsonar.exclusions='**/*.spec.ts' \
  -Dsonar.test.inclusions='**/*.spec.ts' \
  -Dsonar.javascript.lcov.reportPaths="$COVERAGE_REPORT" \
  -Dsonar.qualitygate.wait=true \
  -Dsonar.qualitygate.timeout=300
