#!/usr/bin/env bash

set -euo pipefail

# shellcheck source=lib/sonar-evidence.sh
source "$(dirname "$0")/lib/sonar-evidence.sh"

: "${SONAR_HOST_URL:?SONAR_HOST_URL must be defined in the sonarqube CircleCI context}"
: "${SONAR_TOKEN:?SONAR_TOKEN must be defined in the sonarqube CircleCI context}"

readonly SONAR_PROJECT_KEY="Internship-Proxym"
readonly SONAR_SCANNER_LOG="$(mktemp)"
readonly SONAR_GATE_RESPONSE="$(mktemp)"

report_header "DEVSECOPS PIPELINE - SONARQUBE BACKEND STATIC ANALYSIS"
report_pipeline_context
report_field "Project key" "$SONAR_PROJECT_KEY"
report_field "Scanner" "SonarScanner for Maven 5.7.0.6970"
report_field "Coverage" "JaCoCo XML"
report_field "Quality Gate" "WAITING"
report_footer

cleanup_sonar_files() {
  rm -f -- "$SONAR_SCANNER_LOG" "$SONAR_GATE_RESPONSE"
}

trap cleanup_sonar_files EXIT

coverage_report_count="$(find . -path '*/target/site/jacoco/jacoco.xml' -type f | wc -l)"
scanner_status=0
set +e
mvn -B -ntp \
  org.sonarsource.scanner.maven:sonar-maven-plugin:5.7.0.6970:sonar \
  -Dsonar.projectKey="$SONAR_PROJECT_KEY" \
  -Dsonar.projectName='Internship Proxym' \
  -Dsonar.host.url="$SONAR_HOST_URL" \
  -Dsonar.token="$SONAR_TOKEN" \
  -Dsonar.qualitygate.wait=true \
  -Dsonar.qualitygate.timeout=300 \
  2>&1 | tee "$SONAR_SCANNER_LOG"
scanner_status="${PIPESTATUS[0]}"
set -e

if grep -Eq 'QUALITY GATE STATUS: (PASSED|FAILED)' "$SONAR_SCANNER_LOG"; then
  sonar_fetch_quality_gate \
    "$SONAR_PROJECT_KEY" "$SONAR_TOKEN" "$SONAR_GATE_RESPONSE" || true
fi

report_sonar_evidence \
  "SONARQUBE BACKEND SUMMARY" \
  "$SONAR_PROJECT_KEY" \
  "${coverage_report_count} JaCoCo XML report(s)" \
  "$scanner_status" \
  "$SONAR_SCANNER_LOG" \
  "$SONAR_GATE_RESPONSE"

exit "$scanner_status"
