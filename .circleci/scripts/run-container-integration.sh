#!/usr/bin/env bash

set -euo pipefail

source "$(dirname "$0")/lib/application-images.sh"

configure_candidate_images
configure_runtime_environment
ensure_jq
mkdir -p reports
trap collect_compose_logs_and_cleanup EXIT

load_candidate_images
wait_for_application_stack
