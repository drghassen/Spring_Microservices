#!/bin/sh

set -eu

mkdir -p reports

trivy fs \
  --scanners vuln,secret,misconfig \
  --severity HIGH,CRITICAL \
  --exit-code 0 \
  --format json \
  --output reports/trivy-filesystem.json \
  --no-progress \
  --skip-version-check \
  --timeout 20m \
  .

trivy fs \
  --scanners vuln,secret,misconfig \
  --severity HIGH,CRITICAL \
  --exit-code 1 \
  --no-progress \
  --skip-version-check \
  --timeout 20m \
  .
