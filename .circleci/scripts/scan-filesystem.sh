#!/bin/sh

set -eu

mkdir -p reports

trivy fs \
  --scanners secret,misconfig \
  --misconfig-scanners dockerfile \
  --severity HIGH,CRITICAL \
  --exit-code 0 \
  --format json \
  --output reports/trivy-filesystem.json \
  --offline-scan \
  --skip-dirs reports \
  --no-progress \
  --skip-version-check \
  --timeout 20m \
  .

trivy fs \
  --scanners secret,misconfig \
  --misconfig-scanners dockerfile \
  --severity HIGH,CRITICAL \
  --exit-code 1 \
  --offline-scan \
  --skip-dirs reports \
  --no-progress \
  --skip-version-check \
  --timeout 20m \
  .
