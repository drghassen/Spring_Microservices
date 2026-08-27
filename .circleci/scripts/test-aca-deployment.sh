#!/usr/bin/env bash

set -euo pipefail

REPOSITORY_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
readonly REPOSITORY_ROOT
readonly DEPLOY_SCRIPT="${REPOSITORY_ROOT}/.circleci/scripts/deploy-aca.sh"
readonly CONTINUE_CONFIG="${REPOSITORY_ROOT}/.circleci/continue-config.yml"
readonly ROOT_CONFIG="${REPOSITORY_ROOT}/.circleci/config.yml"
readonly ROOT_MAIN="${REPOSITORY_ROOT}/ACA/main.tf"
readonly ROOT_VARIABLES="${REPOSITORY_ROOT}/ACA/variables.tf"
readonly DATA_OUTPUTS="${REPOSITORY_ROOT}/ACA/modules/data/outputs.tf"
readonly DATA_MAIN="${REPOSITORY_ROOT}/ACA/modules/data/main.tf"
readonly APP_LOCALS="${REPOSITORY_ROOT}/ACA/modules/apps/locals.tf"
readonly OIDC_AUDIT="${REPOSITORY_ROOT}/.circleci/scripts/azure-oidc-audit.sh"

# The suite deliberately replaces sourced functions with local Azure/Terraform mocks.
# shellcheck disable=SC2317
# shellcheck source-path=SCRIPTDIR
# shellcheck source=deploy-aca.sh
source "$DEPLOY_SCRIPT"

TEST_COUNT=0

pass() {
  TEST_COUNT=$((TEST_COUNT + 1))
  printf 'PASS: %s\n' "$1"
}

assert_succeeds() {
  local name="$1"
  shift
  if ("$@") >/tmp/aca-mock-test.out 2>/tmp/aca-mock-test.err; then
    pass "$name"
  else
    printf 'FAIL: %s\n' "$name" >&2
    sed -n '1,30p' /tmp/aca-mock-test.err >&2
    exit 1
  fi
}

assert_fails() {
  local name="$1"
  shift
  if ("$@") >/tmp/aca-mock-test.out 2>/tmp/aca-mock-test.err; then
    printf 'FAIL: %s unexpectedly succeeded.\n' "$name" >&2
    exit 1
  fi
  pass "$name"
}

foundation_state() {
  STATE_RESOURCE_ADDRESSES=("${ACA_REQUIRED_STATE_ADDRESSES[@]}")
}

complete_state() {
  local application
  foundation_state
  for application in "${ACA_APPLICATIONS[@]}"; do
    STATE_RESOURCE_ADDRESSES+=("module.apps.azurerm_container_app.this[\"${application}\"]")
  done
  STATE_RESOURCE_ADDRESSES+=('module.apps.azurerm_container_app_job.database_migrations')
}

test_initial_mode() {
  foundation_state
  AZURE_APPLICATION_NAMES=()
  AZURE_MIGRATION_JOB_EXISTS=0
  detect_release_mode >/dev/null
  [[ "$DETECTED_RELEASE_MODE" == "initial" ]]
}

test_redeploy_mode() {
  complete_state
  AZURE_APPLICATION_NAMES=("${ACA_APPLICATIONS[@]}")
  AZURE_MIGRATION_JOB_EXISTS=1
  detect_release_mode >/dev/null
  [[ "$DETECTED_RELEASE_MODE" == "redeploy" ]]
}

test_partial_mode() {
  local count="$1"
  local index
  foundation_state
  AZURE_APPLICATION_NAMES=()
  for ((index = 0; index < count; index++)); do
    AZURE_APPLICATION_NAMES+=("${ACA_APPLICATIONS[$index]}")
  done
  AZURE_MIGRATION_JOB_EXISTS=0
  detect_release_mode
}

test_job_state_inconsistency() {
  foundation_state
  AZURE_APPLICATION_NAMES=()
  AZURE_MIGRATION_JOB_EXISTS=1
  detect_release_mode
}

mock_migration_success() {
  local execution_arguments="${TMPDIR:-/tmp}/aca-execution-arguments"
  : >"$execution_arguments"
  az() {
    if [[ "$*" == *"containerapp job start"* ]]; then
      printf '%s\n' 'execution-started-by-this-release'
    elif [[ "$*" == *"containerapp job execution show"* ]]; then
      printf '%s\n' "$*" >>"$execution_arguments"
      printf '%s\n' 'Succeeded'
    fi
  }
  run_database_migrations >/dev/null
  grep -q -- '--job-execution-name execution-started-by-this-release' "$execution_arguments"
}

mock_migration_failed() {
  az() {
    if [[ "$*" == *"containerapp job start"* ]]; then
      printf '%s\n' 'execution-current'
    else
      printf '%s\n' 'Failed'
    fi
  }
  run_database_migrations
}

mock_migration_timeout() {
  MIGRATIONS_TIMEOUT_SECONDS=1 MIGRATIONS_POLL_INTERVAL_SECONDS=1 \
    bash -c '
      set -euo pipefail
      source "$1"
      az() {
        if [[ "$*" == *"containerapp job start"* ]]; then
          printf "%s\n" execution-current
        else
          printf "%s\n" Running
        fi
      }
      run_database_migrations
    ' _ "$DEPLOY_SCRIPT"
}

populate_digest_maps() {
  local application
  for application in "${ACA_APPLICATIONS[@]}"; do
    DESIRED_APPLICATION_DIGESTS["$application"]="sha256:$(printf 'd%.0s' {1..64})"
    CURRENT_APPLICATION_DIGESTS["$application"]="sha256:$(printf 'c%.0s' {1..64})"
  done
  DESIRED_MIGRATION_DIGEST="sha256:$(printf 'a%.0s' {1..64})"
  CURRENT_MIGRATION_DIGEST="sha256:$(printf 'b%.0s' {1..64})"
}

test_initial_rollout() {
  local event_file="${TMPDIR:-/tmp}/aca-initial-events"
  : >"$event_file"
  populate_digest_maps
  DETECTED_RELEASE_MODE=initial
  copy_digest_map DESIRED_APPLICATION_DIGESTS ROLLOUT_APPLICATION_DIGESTS
  safe_plan_and_apply() {
    printf 'plan:%s:%s\n' "$1" "$5" >>"$event_file"
  }
  run_database_migrations() { printf '%s\n' migration >>"$event_file"; }
  latest_revision_name() { printf '%s-revision\n' "$1"; }
  wait_for_healthy_revision() { printf 'healthy:%s\n' "$1" >>"$event_file"; }
  run_post_deployment_health_checks() { printf '%s\n' post-health >>"$event_file"; }
  run_deployment >/dev/null
  grep -q '^plan:infrastructure-bootstrap:\[\]$' "$event_file"
  [[ "$(grep -n '^migration$' "$event_file" | cut -d: -f1)" -lt \
    "$(grep -n '^healthy:config-server$' "$event_file" | cut -d: -f1)" ]]
  [[ "$(grep -c '^healthy:' "$event_file")" == 9 ]]
}

test_redeploy_migration_gate() {
  local event_file="${TMPDIR:-/tmp}/aca-redeploy-events"
  local migration_complete=0
  local application
  : >"$event_file"
  populate_digest_maps
  DETECTED_RELEASE_MODE=redeploy
  copy_digest_map CURRENT_APPLICATION_DIGESTS ROLLOUT_APPLICATION_DIGESTS
  safe_plan_and_apply() {
    if ((migration_complete == 0)); then
      for application in "${ACA_APPLICATIONS[@]}"; do
        [[ "${ROLLOUT_APPLICATION_DIGESTS[$application]}" == \
          "${CURRENT_APPLICATION_DIGESTS[$application]}" ]]
      done
    fi
    printf 'plan:%s\n' "$1" >>"$event_file"
  }
  run_database_migrations() { migration_complete=1; printf '%s\n' migration >>"$event_file"; }
  latest_revision_name() { printf '%s-revision\n' "$1"; }
  wait_for_healthy_revision() { printf 'healthy:%s\n' "$1" >>"$event_file"; }
  run_post_deployment_health_checks() { :; }
  run_deployment >/dev/null
  [[ "$(grep -c '^healthy:' "$event_file")" == 9 ]]
  [[ "$(grep -n '^migration$' "$event_file" | cut -d: -f1)" -lt \
    "$(grep -n '^healthy:config-server$' "$event_file" | cut -d: -f1)" ]]
}

test_revision_health_failure() {
  local application="$1"
  az() {
    if [[ "$*" == *"revision show"* ]]; then
      printf '%s\t%s\n' Unhealthy Provisioned
    else
      printf '%s\n' "${application}-revision"
    fi
  }
  wait_for_healthy_revision "$application" "${application}-revision"
}

write_plan_fixture() {
  local file="$1" actions="$2" address="${3:-module.apps.azurerm_container_app.this[\"client\"]}"
  jq -n --arg address "$address" --argjson actions "$actions" '{
    resource_changes: [{
      address: $address,
      change: {
        actions: $actions,
        after_sensitive: {secret: true},
        after: {secret: "fixture-value-never-print"}
      }
    }]
  }' >"$file"
}

test_plan_delete_refusal() {
  local fixture
  fixture="$(mktemp)"
  write_plan_fixture "$fixture" '["delete"]'
  inspect_plan_json "$fixture" deletion none
}

test_plan_replacement_refusal() {
  local fixture
  fixture="$(mktemp)"
  write_plan_fixture "$fixture" '["delete","create"]'
  inspect_plan_json "$fixture" replacement initial-apps-job
}

test_plan_sensitive_value_not_logged() {
  local fixture output
  fixture="$(mktemp)"
  write_plan_fixture "$fixture" '["update"]'
  output="$(inspect_plan_json "$fixture" sensitive-plan none)"
  [[ "$output" != *'fixture-value-never-print'* ]]
}

test_pre_migration_app_change_refusal() {
  local fixture
  fixture="$(mktemp)"
  write_plan_fixture "$fixture" '["update"]'
  inspect_plan_json "$fixture" pre-migration pre-migration
}

test_cosmos_derivation() {
  grep -q 'resource "azurerm_cosmosdb_account" "mongodb"' "$DATA_MAIN"
  grep -q 'azurerm_cosmosdb_account.mongodb.primary_mongodb_connection_string' "$DATA_OUTPUTS"
  grep -A4 'output "cosmos_mongodb_uri"' "$DATA_OUTPUTS" | grep -q 'sensitive[[:space:]]*=[[:space:]]*true'
  grep -q 'cosmos_mongodb_uri[[:space:]]*=[[:space:]]*module.data.cosmos_mongodb_uri' "$ROOT_MAIN"
  grep -q 'mongo-uri[[:space:]]*=[[:space:]]*var.cosmos_mongodb_uri' "$APP_LOCALS"
  if grep -q 'variable "cosmos_mongodb_uri"' "$ROOT_VARIABLES"; then return 1; fi
  if grep -q 'TF_VAR_cosmos_mongodb_uri' "$DEPLOY_SCRIPT" "$CONTINUE_CONFIG" "$ROOT_CONFIG"; then return 1; fi
  if grep -q 'output "cosmos_mongodb_uri"' "${REPOSITORY_ROOT}/ACA/outputs.tf"; then return 1; fi
}

test_oidc_audit_read_only() {
  grep -q 'storage blob show' "$OIDC_AUDIT"
  grep -q 'TFSTATE_WRITE=NOT_TESTED' "$OIDC_AUDIT"
  if grep -Eq 'storage blob (upload|delete|update|sync)' "$OIDC_AUDIT"; then return 1; fi
}

test_circleci_serial_gate() {
  grep -q 'serial-group: << pipeline.project.slug >>/aca-production-deployment' "$CONTINUE_CONFIG"
  grep -A8 -- '- hold-aca-deployment:' "$CONTINUE_CONFIG" | grep -q -- '- plan-aca'
  grep -A8 -- '- hold-aca-deployment:' "$CONTINUE_CONFIG" | grep -q -- '- release-acr'
  if grep -A8 -- '- hold-aca-deployment:' "$CONTINUE_CONFIG" | grep -q 'context:'; then return 1; fi
}

assert_succeeds "automatic initial installation mode" test_initial_mode
assert_succeeds "automatic complete redeployment mode" test_redeploy_mode
for partial_count in {1..8}; do
  assert_fails "partial state with ${partial_count}/9 applications" test_partial_mode "$partial_count"
done
assert_fails "migration job/state inconsistency" test_job_state_inconsistency
assert_succeeds "migration success and exact execution tracking" mock_migration_success
assert_fails "migration Failed stops release" mock_migration_failed
assert_fails "migration timeout stops release" mock_migration_timeout
assert_succeeds "initial migration-gated ordered rollout" test_initial_rollout
assert_succeeds "redeploy keeps all application digests unchanged before migration" test_redeploy_migration_gate
assert_fails "Config Server unhealthy revision stops release" test_revision_health_failure config-server
assert_fails "Discovery unhealthy revision stops release" test_revision_health_failure discovery-service
assert_fails "Gateway unhealthy revision stops release" test_revision_health_failure gateway
assert_fails "Terraform delete action is refused" test_plan_delete_refusal
assert_fails "Terraform delete/create replacement is refused" test_plan_replacement_refusal
assert_fails "Container App update before migration is refused" test_pre_migration_app_change_refusal
assert_succeeds "sensitive plan value is absent from summary" test_plan_sensitive_value_not_logged
assert_succeeds "Cosmos URI is derived, injected, sensitive, and not context-driven" test_cosmos_derivation
assert_succeeds "OIDC state audit is read-only and does not infer write" test_oidc_audit_read_only
assert_succeeds "CircleCI approval and stable serial group block concurrent deployment" test_circleci_serial_gate

printf 'ACA deployment mock suite passed: %s checks.\n' "$TEST_COUNT"
