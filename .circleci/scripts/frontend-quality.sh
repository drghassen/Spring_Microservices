#!/usr/bin/env bash

set -euo pipefail

# shellcheck source=lib/report-evidence.sh
source "$(dirname "$0")/lib/report-evidence.sh"

report_header "DEVSECOPS PIPELINE - FRONTEND BUILD & TEST"
report_pipeline_context
report_field "Framework" "Angular"
report_field "Package manager" "npm"
report_field "Test browser" "ChromeHeadless"
report_field "Build configuration" "production"
report_footer

report_section "Installing locked frontend dependencies"
npm ci --prefix UI_Spring

report_section "Running Angular unit tests with coverage"
npm run test --prefix UI_Spring -- --watch=false --browsers=ChromeHeadless --code-coverage

report_section "Building the Angular production bundle"
npm run build --prefix UI_Spring -- --configuration=production

readonly coverage_report="UI_Spring/coverage/ui-spring/lcov.info"
[[ -f "$coverage_report" ]] || {
  echo "Frontend coverage report not found: $coverage_report" >&2
  exit 1
}

mkdir -p ci-frontend-sonar
cp "$coverage_report" ci-frontend-sonar/lcov.info

report_header "FRONTEND BUILD & TEST SUMMARY"
report_field "Unit tests" "PASSED"
report_field "Code coverage" "GENERATED"
report_field "Production build" "PASSED"
report_field "Build output" "UI_Spring/dist/ui-spring"
report_field "RESULT" "FRONTEND BUILD & TEST PASSED"
report_footer
