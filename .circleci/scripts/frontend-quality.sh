#!/usr/bin/env bash

set -euo pipefail

npm ci --prefix UI_Spring
npm run test --prefix UI_Spring -- --watch=false --browsers=ChromeHeadless --code-coverage
npm run build --prefix UI_Spring -- --configuration=production

readonly coverage_report="UI_Spring/coverage/ui-spring/lcov.info"
[[ -f "$coverage_report" ]] || {
  echo "Frontend coverage report not found: $coverage_report" >&2
  exit 1
}

mkdir -p ci-frontend-sonar
cp "$coverage_report" ci-frontend-sonar/lcov.info
