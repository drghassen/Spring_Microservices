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
readonly ACA_PREFLIGHT="${REPOSITORY_ROOT}/.circleci/scripts/aca-preflight.sh"

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
  local event_file="${TMPDIR:-/tmp}/aca-initial-events" output_file rollout_phases
  : >"$event_file"
  output_file="$(mktemp)"
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
  run_deployment >"$output_file"
  grep -Fxq "plan:infrastructure-bootstrap:${NO_ACTIVE_APPLICATIONS}" "$event_file"
  grep -Fxq "plan:migration-job:${NO_ACTIVE_APPLICATIONS}" "$event_file"
  grep -Fxq "plan:config-server:${CONFIG_ACTIVE_APPLICATIONS}" "$event_file"
  grep -Fxq "plan:discovery-service:${DISCOVERY_ACTIVE_APPLICATIONS}" "$event_file"
  grep -Fxq "plan:gateway:${GATEWAY_ACTIVE_APPLICATIONS}" "$event_file"
  grep -Fxq "plan:games-service:${GAMES_ACTIVE_APPLICATIONS}" "$event_file"
  grep -Fxq "plan:library-service:${LIBRARY_ACTIVE_APPLICATIONS}" "$event_file"
  grep -Fxq "plan:order-service:${ORDER_ACTIVE_APPLICATIONS}" "$event_file"
  grep -Fxq "plan:payment-service:${PAYMENT_ACTIVE_APPLICATIONS}" "$event_file"
  grep -Fxq "plan:user-service:${BUSINESS_ACTIVE_APPLICATIONS}" "$event_file"
  grep -Fxq "plan:client:${ALL_ACTIVE_APPLICATIONS}" "$event_file"
  rollout_phases="$(grep '^plan:' "$event_file" | cut -d: -f2 | tail -n 9)"
  [[ "$(grep -c '^plan:' "$event_file")" == 11 ]]
  [[ "$rollout_phases" == $'config-server\ndiscovery-service\ngateway\ngames-service\nlibrary-service\norder-service\npayment-service\nuser-service\nclient' ]]
  grep -Eq '^Timing: complete ACA deployment = [0-9]+s$' "$output_file"
  [[ "$(grep -c '^migration$' "$event_file")" == 1 ]]
  [[ "$(grep -n '^migration$' "$event_file" | cut -d: -f1)" -lt \
    "$(grep -n '^healthy:config-server$' "$event_file" | cut -d: -f1)" ]]
  [[ "$(grep -c '^healthy:' "$event_file")" == 9 ]]
}

test_redeploy_migration_gate() {
  local event_file="${TMPDIR:-/tmp}/aca-redeploy-events" rollout_phases
  local migration_complete=0
  local candidate_application changed_count
  local -A simulated_application_digests=()
  : >"$event_file"
  populate_digest_maps
  DETECTED_RELEASE_MODE=redeploy
  copy_digest_map CURRENT_APPLICATION_DIGESTS ROLLOUT_APPLICATION_DIGESTS
  copy_digest_map CURRENT_APPLICATION_DIGESTS simulated_application_digests
  safe_plan_and_apply() {
    if ((migration_complete == 0)); then
      for candidate_application in "${ACA_APPLICATIONS[@]}"; do
        [[ "${ROLLOUT_APPLICATION_DIGESTS[$candidate_application]}" == \
          "${CURRENT_APPLICATION_DIGESTS[$candidate_application]}" ]]
      done
    elif [[ "$1" != "infrastructure-bootstrap" && "$1" != "migration-job" ]]; then
      changed_count=0
      for candidate_application in "${ACA_APPLICATIONS[@]}"; do
        if [[ "${ROLLOUT_APPLICATION_DIGESTS[$candidate_application]}" != \
          "${simulated_application_digests[$candidate_application]}" ]]; then
          changed_count=$((changed_count + 1))
          simulated_application_digests["$candidate_application"]="${ROLLOUT_APPLICATION_DIGESTS[$candidate_application]}"
        fi
      done
      if [[ "$1" == "business-services" ]]; then
        [[ "$changed_count" == "${#BUSINESS_REDEPLOY_APPLICATIONS[@]}" ]]
        [[ "$(jq -cS . <<<"$7")" == \
          "$(jq -cnS --args '$ARGS.positional' "${BUSINESS_REDEPLOY_APPLICATIONS[@]}")" ]]
      else
        [[ "$changed_count" == 1 ]]
      fi
    fi
    printf 'plan:%s:%s\n' "$1" "$5" >>"$event_file"
  }
  run_database_migrations() { migration_complete=1; printf '%s\n' migration >>"$event_file"; }
  latest_revision_name() { printf '%s-revision\n' "$1"; }
  wait_for_healthy_revision() { printf 'healthy:%s\n' "$1" >>"$event_file"; }
  run_post_deployment_health_checks() { printf '%s\n' post-health >>"$event_file"; }
  run_deployment >"${TMPDIR:-/tmp}/aca-redeploy-output"
  rollout_phases="$(grep '^plan:' "$event_file" | cut -d: -f2 | tail -n 5)"
  [[ "$(grep -c '^plan:' "$event_file")" == 7 ]]
  [[ "$rollout_phases" == $'config-server\ndiscovery-service\ngateway\nbusiness-services\nclient' ]]
  [[ "$(grep -Fc ":${ALL_ACTIVE_APPLICATIONS}" "$event_file")" == 7 ]]
  [[ "$(grep -c '^migration$' "$event_file")" == 1 ]]
  [[ "$(grep -c '^healthy:' "$event_file")" == 9 ]]
  [[ "$(grep -n '^migration$' "$event_file" | cut -d: -f1)" -lt \
    "$(grep -n '^healthy:config-server$' "$event_file" | cut -d: -f1)" ]]
  [[ "$(grep -n '^healthy:gateway$' "$event_file" | cut -d: -f1)" -lt \
    "$(grep -n '^healthy:games-service$' "$event_file" | cut -d: -f1)" ]]
  [[ "$(grep -n '^healthy:order-service$' "$event_file" | cut -d: -f1)" -lt \
    "$(grep -n '^healthy:client$' "$event_file" | cut -d: -f1)" ]]
  [[ "$(grep -n '^healthy:client$' "$event_file" | cut -d: -f1)" -lt \
    "$(grep -n '^post-health$' "$event_file" | cut -d: -f1)" ]]
  grep -Eq '^Timing: business-services rollout = [0-9]+s$' \
    "${TMPDIR:-/tmp}/aca-redeploy-output"
}

test_revision_health_condition() {
  local condition="$1"
  az() {
    if [[ "$*" == *"revision show"* ]]; then
      case "$condition" in
        healthy | wrong-ready) printf '%s\n%s\n' Healthy Provisioned ;;
        unhealthy) printf '%s\n%s\n' Unhealthy Provisioned ;;
        failed) printf '%s\n%s\n' Healthy Failed ;;
        non-provisioned) printf '%s\n%s\n' Healthy Provisioning ;;
      esac
    else
      if [[ "$condition" == "wrong-ready" ]]; then
        printf '%s\n' 'fixture-old-revision'
      else
        printf '%s\n' 'fixture-expected-revision'
      fi
    fi
  }
  sleep() {
    SECONDS=$((SECONDS + APP_HEALTH_TIMEOUT_SECONDS))
  }
  wait_for_healthy_revision fixture-app fixture-expected-revision
}

test_multiline_revision_parsing() {
  local -a revision_details=()

  parse_exact_required_tsv_lines 3 $'Healthy\nProvisioned\nexample.azurecr.io/app@sha256:fixture' \
    revision_details
  [[ "${revision_details[0]}" == "Healthy" ]]
  [[ "${revision_details[1]}" == "Provisioned" ]]
  [[ "${revision_details[2]}" == "example.azurecr.io/app@sha256:fixture" ]]
}

test_post_deployment_http_checks_only() {
  local event_file
  event_file="$(mktemp)"
  az() {
    [[ "$*" == *'containerapp show --name client'* ]] || return 1
    printf '%s\n' 'client.example.test'
  }
  assert_public_http_status() {
    printf '%s|%s|%s\n' "$1" "$2" "$3" >>"$event_file"
  }
  run_post_deployment_health_checks >/dev/null
  grep -Fxq 'client|https://client.example.test/|200' "$event_file"
  grep -Fxq 'public Gateway games route|https://client.example.test/api/v1/games|200' "$event_file"
  [[ "$(wc -l <"$event_file")" == 2 ]]
}

test_no_deployment_exec_check_remains() {
  if grep -Eq 'az[[:space:]]+containerapp[[:space:]]+exec' "$DEPLOY_SCRIPT"; then return 1; fi
}

test_zero_change_plan_skips_apply() {
  local planned=0 applied=0
  create_safe_plan() {
    planned=1
    LAST_PLAN_ADD_COUNT=0
    LAST_PLAN_CHANGE_COUNT=0
    LAST_PLAN_DESTROY_COUNT=0
  }
  apply_validated_plan() { applied=$((applied + 1)); }

  safe_plan_and_apply fixture "zero-change fixture"
  [[ "$planned" == 1 && "$applied" == 0 ]]
}

test_changed_plan_applies_exact_saved_plan() {
  local planned=0 applied=0
  create_safe_plan() {
    planned=1
    LAST_PLAN_FILE='/tmp/exact-validated-fixture.tfplan'
    LAST_PLAN_ADD_COUNT=0
    LAST_PLAN_CHANGE_COUNT=1
    LAST_PLAN_DESTROY_COUNT=0
  }
  apply_validated_plan() {
    [[ "$1" == "changed fixture" ]]
    [[ "$LAST_PLAN_FILE" == '/tmp/exact-validated-fixture.tfplan' ]]
    applied=$((applied + 1))
  }

  safe_plan_and_apply fixture "changed fixture"
  [[ "$planned" == 1 && "$applied" == 1 ]]
}

test_business_wave_single_saved_plan_apply() {
  local planned=0 applied=0 application
  local event_file expected_allowlist
  event_file="$(mktemp)"
  populate_digest_maps
  copy_digest_map CURRENT_APPLICATION_DIGESTS ROLLOUT_APPLICATION_DIGESTS
  expected_allowlist='["games-service","library-service","payment-service","user-service","order-service"]'
  [[ "${BUSINESS_REDEPLOY_APPLICATIONS[*]}" == \
    "games-service library-service payment-service user-service order-service" ]]
  create_safe_plan() {
    planned=$((planned + 1))
    [[ "$1" == "business-services" ]]
    [[ "$2" == "Business services revisions" ]]
    [[ "$5" == "$ALL_ACTIVE_APPLICATIONS" ]]
    [[ "$(jq -c . <<<"$7")" == "$expected_allowlist" ]]
    LAST_PLAN_FILE='/tmp/business-services-fixture.tfplan'
    LAST_PLAN_ADD_COUNT=0
    LAST_PLAN_CHANGE_COUNT=5
    LAST_PLAN_DESTROY_COUNT=0
  }
  apply_validated_plan() {
    [[ "$1" == "Business services revisions" ]]
    [[ "$LAST_PLAN_FILE" == '/tmp/business-services-fixture.tfplan' ]]
    applied=$((applied + 1))
  }
  latest_revision_name() {
    printf 'capture:%s\n' "$1" >>"$event_file"
    printf '%s-revision\n' "$1"
  }
  wait_for_healthy_revision() {
    [[ "$2" == "$1-revision" ]]
    printf 'healthy:%s\n' "$1" >>"$event_file"
  }

  deploy_application_wave business-services "Business services revisions" \
    "${BUSINESS_REDEPLOY_APPLICATIONS[@]}"

  [[ "$planned" == 1 && "$applied" == 1 ]]
  [[ "$(grep -c '^capture:' "$event_file")" == 5 ]]
  [[ "$(grep -c '^healthy:' "$event_file")" == 5 ]]
  [[ "$(grep '^healthy:' "$event_file" | cut -d: -f2)" == \
    $'games-service\nlibrary-service\npayment-service\nuser-service\norder-service' ]]
  for application in "${BUSINESS_REDEPLOY_APPLICATIONS[@]}"; do
    [[ "${ROLLOUT_APPLICATION_DIGESTS[$application]}" == \
      "${DESIRED_APPLICATION_DIGESTS[$application]}" ]]
  done
  [[ "${ROLLOUT_APPLICATION_DIGESTS[client]}" == \
    "${CURRENT_APPLICATION_DIGESTS[client]}" ]]
}

test_business_wave_zero_change_skips_apply() {
  local planned=0 applied=0 revision_queries=0 waits=0
  populate_digest_maps
  copy_digest_map DESIRED_APPLICATION_DIGESTS ROLLOUT_APPLICATION_DIGESTS
  create_safe_plan() {
    planned=$((planned + 1))
    [[ "$7" == '[]' ]]
    LAST_PLAN_ADD_COUNT=0
    LAST_PLAN_CHANGE_COUNT=0
    LAST_PLAN_DESTROY_COUNT=0
  }
  apply_validated_plan() { applied=$((applied + 1)); }
  latest_revision_name() { revision_queries=$((revision_queries + 1)); }
  wait_for_healthy_revision() { waits=$((waits + 1)); }

  deploy_application_wave business-services "Business services revisions" \
    "${BUSINESS_REDEPLOY_APPLICATIONS[@]}" >/dev/null
  [[ "$planned" == 1 && "$applied" == 0 ]]
  [[ "$revision_queries" == 0 && "$waits" == 0 ]]
}

test_business_wave_partial_change_waits_only_changed() {
  local event_file application
  event_file="$(mktemp)"
  populate_digest_maps
  copy_digest_map DESIRED_APPLICATION_DIGESTS ROLLOUT_APPLICATION_DIGESTS
  ROLLOUT_APPLICATION_DIGESTS[client]="${CURRENT_APPLICATION_DIGESTS[client]}"
  for application in library-service payment-service order-service; do
    ROLLOUT_APPLICATION_DIGESTS["$application"]="${CURRENT_APPLICATION_DIGESTS[$application]}"
  done
  safe_plan_and_apply() {
    [[ "$1" == "business-services" && "$5" == "$ALL_ACTIVE_APPLICATIONS" ]]
    [[ "$(jq -c . <<<"$7")" == \
      '["library-service","payment-service","order-service"]' ]]
  }
  latest_revision_name() { printf '%s-revision\n' "$1"; }
  wait_for_healthy_revision() { printf '%s\n' "$1" >>"$event_file"; }

  deploy_application_wave business-services "Business services revisions" \
    "${BUSINESS_REDEPLOY_APPLICATIONS[@]}"

  [[ "$(cat "$event_file")" == $'library-service\npayment-service\norder-service' ]]
  for application in "${BUSINESS_REDEPLOY_APPLICATIONS[@]}"; do
    [[ "${ROLLOUT_APPLICATION_DIGESTS[$application]}" == \
      "${DESIRED_APPLICATION_DIGESTS[$application]}" ]]
  done
  [[ "${ROLLOUT_APPLICATION_DIGESTS[client]}" == \
    "${CURRENT_APPLICATION_DIGESTS[client]}" ]]
}

test_business_wave_one_failed_revision_fails_wave() {
  populate_digest_maps
  copy_digest_map CURRENT_APPLICATION_DIGESTS ROLLOUT_APPLICATION_DIGESTS
  safe_plan_and_apply() { :; }
  latest_revision_name() { printf '%s-revision\n' "$1"; }
  wait_for_healthy_revision() {
    [[ "$1" != "payment-service" ]]
  }

  deploy_application_wave business-services "Business services revisions" \
    "${BUSINESS_REDEPLOY_APPLICATIONS[@]}"
}

test_no_concurrent_terraform_apply() {
  local apply_function
  apply_function="$(sed -n '/^apply_validated_plan()/,/^}/p' "$DEPLOY_SCRIPT")"
  [[ "$(grep -Fc 'terraform -chdir="$ACA_TERRAFORM_DIRECTORY" apply \' \
    <<<"$apply_function")" == 1 ]]
  if grep -Eq '(^|[[:space:]])wait([[:space:]]|$)|&[[:space:]]*$' <<<"$apply_function"; then
    return 1
  fi
}

test_timing_diagnostics_exclude_arguments() {
  local output sensitive_value='fixture-sensitive-timing-value-never-print'
  timed_fixture() {
    SECONDS=$((SECONDS + 3))
    [[ "$1" == "$sensitive_value" ]]
  }
  output="$(run_timed_phase 'safe fixture phase' timed_fixture "$sensitive_value")"
  [[ "$output" == 'Timing: safe fixture phase = 3s' ]]
  [[ "$output" != *"$sensitive_value"* ]]
}

write_plan_fixture() {
  local file="$1" actions="$2"
  local address="${3:-module.apps.azurerm_container_app.this[\"client\"]}"
  local before after before_sensitive after_sensitive
  if (( $# >= 7 )); then
    before="$4"
    after="$5"
    before_sensitive="$6"
    after_sensitive="$7"
  else
    before='{"secret":"fixture-before-never-print"}'
    after='{"secret":"fixture-after-never-print"}'
    before_sensitive='{"secret":true}'
    after_sensitive='{"secret":true}'
  fi
  jq -n --arg address "$address" --argjson actions "$actions" \
    --argjson before "$before" --argjson after "$after" \
    --argjson before_sensitive "$before_sensitive" \
    --argjson after_sensitive "$after_sensitive" '{
    resource_changes: [{
      address: $address,
      change: {
        actions: $actions,
        before: $before,
        after: $after,
        before_sensitive: $before_sensitive,
        after_sensitive: $after_sensitive
      }
    }]
  }' >"$file"
}

test_normal_redeploy_no_changes() {
  local fixture
  fixture="$(mktemp)"
  write_plan_fixture "$fixture" '["no-op"]' \
    'module.apps.azurerm_container_app.this["client"]' '{}' '{}' '{}' '{}'
  inspect_plan_json "$fixture" normal-redeploy pre-migration
}

test_application_image_update_after_migration_allowed() {
  local fixture
  fixture="$(mktemp)"
  write_plan_fixture "$fixture" '["update"]' \
    'module.apps.azurerm_container_app.this["client"]' \
    '{"template":[{"container":[{"image":"fixture-current"}]}]}' \
    '{"template":[{"container":[{"image":"fixture-candidate"}]}]}' '{}' '{}'
  inspect_plan_json "$fixture" application-rollout none
}

test_business_wave_unexpected_client_change_refused() {
  local fixture allowed_applications
  fixture="$(mktemp)"
  allowed_applications='["games-service","library-service","payment-service","user-service","order-service"]'
  write_plan_fixture "$fixture" '["update"]' \
    'module.apps.azurerm_container_app.this["client"]' \
    '{"template":[{"container":[{"image":"fixture-current"}]}]}' \
    '{"template":[{"container":[{"image":"fixture-candidate"}]}]}' '{}' '{}'
  inspect_plan_json "$fixture" business-services none "$allowed_applications"
}

test_business_wave_intended_update_allowed() {
  local fixture allowed_applications
  fixture="$(mktemp)"
  allowed_applications='["games-service","library-service","payment-service","user-service","order-service"]'
  write_plan_fixture "$fixture" '["update"]' \
    'module.apps.azurerm_container_app.this["games-service"]' \
    '{"template":[{"container":[{"image":"fixture-current"}]}]}' \
    '{"template":[{"container":[{"image":"fixture-candidate"}]}]}' '{}' '{}'
  inspect_plan_json "$fixture" business-services none "$allowed_applications"
}

test_business_wave_foundation_update_refused() {
  local fixture allowed_applications
  fixture="$(mktemp)"
  allowed_applications='["games-service","library-service","payment-service","user-service","order-service"]'
  write_plan_fixture "$fixture" '["update"]' \
    'module.foundation.azurerm_log_analytics_workspace.this' \
    '{"retention_in_days":30}' '{"retention_in_days":60}' '{}' '{}'
  inspect_plan_json "$fixture" business-services none "$allowed_applications"
}

test_migration_job_image_update_before_migration_allowed() {
  local fixture
  fixture="$(mktemp)"
  write_plan_fixture "$fixture" '["update"]' \
    'module.apps.azurerm_container_app_job.database_migrations' \
    '{"template":[{"container":[{"image":"fixture-current"}]}]}' \
    '{"template":[{"container":[{"image":"fixture-candidate"}]}]}' '{}' '{}'
  inspect_plan_json "$fixture" migration-job pre-migration
}

test_pre_migration_attribute_refusal() {
  local attribute="$1" fixture before after
  fixture="$(mktemp)"
  case "$attribute" in
    image)
      before='{"template":[{"container":[{"image":"fixture-current"}]}]}'
      after='{"template":[{"container":[{"image":"fixture-candidate"}]}]}'
      ;;
    scaling)
      before='{"template":[{"min_replicas":1,"max_replicas":2}]}'
      after='{"template":[{"min_replicas":0,"max_replicas":2}]}'
      ;;
    ingress)
      before='{"ingress":[{"external_enabled":false,"target_port":8080}]}'
      after='{"ingress":[{"external_enabled":true,"target_port":8080}]}'
      ;;
    probe)
      before='{"template":[{"container":[{"readiness_probe":[{"path":"/health"}]}]}]}'
      after='{"template":[{"container":[{"readiness_probe":[{"path":"/ready"}]}]}]}'
      ;;
    secret)
      before='{"secret":[{"name":"fixture","value":"fixture-before-never-print"}]}'
      after='{"secret":[{"name":"fixture","value":"fixture-after-never-print"}]}'
      write_plan_fixture "$fixture" '["update"]' \
        'module.apps.azurerm_container_app.this["config-server"]' \
        "$before" "$after" '{"secret":true}' '{"secret":true}'
      inspect_plan_json "$fixture" "pre-migration-${attribute}" pre-migration
      return
      ;;
    *)
      return 2
      ;;
  esac
  write_plan_fixture "$fixture" '["update"]' \
    'module.apps.azurerm_container_app.this["client"]' \
    "$before" "$after" '{}' '{}'
  inspect_plan_json "$fixture" "pre-migration-${attribute}" pre-migration
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
  write_plan_fixture "$fixture" '["update"]' \
    'module.apps.azurerm_container_app.this["config-server"]' \
    '{"secret":[{"name":"fixture","value":"fixture-before-never-print"}]}' \
    '{"secret":[{"name":"fixture","value":"fixture-after-never-print"}]}' \
    '{"secret":true}' '{"secret":true}'
  output="$(inspect_plan_json "$fixture" sensitive-plan pre-migration 2>&1 || true)"
  [[ "$output" == *'changed paths: secret'* ]]
  [[ "$output" != *'fixture-before-never-print'* ]]
  [[ "$output" != *'fixture-after-never-print'* ]]
}

test_unexpected_create_refusal() {
  local fixture
  fixture="$(mktemp)"
  write_plan_fixture "$fixture" '["create"]' 'module.foundation.azurerm_log_analytics_workspace.this' \
    'null' '{"name":"fixture"}' 'false' 'false'
  inspect_plan_json "$fixture" unexpected-create pre-migration
}

test_all_seven_updates_are_classified() {
  local fixture output_file
  fixture="$(mktemp)"
  output_file="$(mktemp)"
  jq -n '
    def app_change($name): {
      address: ("module.apps.azurerm_container_app.this[\"" + $name + "\"]"),
      change: {
        actions: ["update"],
        before: {secret: [{name: "fixture", value: "fixture-before-never-print"}]},
        after: {secret: [{name: "fixture", value: "fixture-after-never-print"}]},
        before_sensitive: {secret: true},
        after_sensitive: {secret: true}
      }
    };
    {
      resource_changes:
        (["config-server", "games-service", "gateway", "order-service", "payment-service", "user-service"]
          | map(app_change(.)))
        + [{
          address: "module.apps.azurerm_container_app_job.database_migrations",
          change: {
            actions: ["update"],
            before: {template: [{container: [{image: "fixture-current"}]}]},
            after: {template: [{container: [{image: "fixture-candidate"}]}]},
            before_sensitive: {},
            after_sensitive: {}
          }
        }]
    }
  ' >"$fixture"

  if inspect_plan_json "$fixture" seven-updates pre-migration >"$output_file" 2>&1; then
    return 1
  fi
  [[ "$LAST_PLAN_CHANGE_COUNT" == 7 ]]
  [[ "$(grep -c '^- module\.apps\.' "$output_file")" == 7 ]]
  grep -Fq -- '- module.apps.azurerm_container_app_job.database_migrations' "$output_file"
  grep -Fq 'changed paths: template[0].container[0].image' "$output_file"
  [[ "$(grep -c 'changed paths: secret' "$output_file")" == 6 ]]
  if grep -q 'fixture-.*-never-print' "$output_file"; then return 1; fi
}

mock_terraform_secret_state() {
  local order_password="${1:-fixture-stable-postgres-app}"
  jq -n --arg order_password "$order_password" '{
    values: {
      root_module: {
        child_modules: [{
          address: "module.apps",
          resources: [
            {address:"module.apps.azurerm_container_app.this[\"config-server\"]",values:{secret:[{name:"jwt-secret",value:"fixture-stable-jwt"}]}},
            {address:"module.apps.azurerm_container_app.this[\"gateway\"]",values:{secret:[{name:"jwt-secret",value:"fixture-stable-jwt"}]}},
            {address:"module.apps.azurerm_container_app.this[\"games-service\"]",values:{secret:[{name:"db-password",value:"fixture-stable-postgres-app"}]}},
            {address:"module.apps.azurerm_container_app.this[\"library-service\"]",values:{secret:[{name:"mongo-uri",value:"fixture-stable-cosmos"}]}},
            {address:"module.apps.azurerm_container_app.this[\"order-service\"]",values:{secret:[{name:"db-password",value:$order_password}]}},
            {address:"module.apps.azurerm_container_app.this[\"payment-service\"]",values:{secret:[{name:"db-password",value:"fixture-stable-postgres-app"}]}},
            {address:"module.apps.azurerm_container_app.this[\"user-service\"]",values:{secret:[
              {name:"mongo-uri",value:"fixture-stable-cosmos"},
              {name:"jwt-secret",value:"fixture-stable-jwt"},
              {name:"admin-password",value:"fixture-stable-admin"}
            ]}},
            {address:"module.apps.azurerm_container_app_job.database_migrations",values:{secret:[
              {name:"postgres-admin-password",value:"fixture-stable-postgres-admin"},
              {name:"postgres-app-password",value:"fixture-stable-postgres-app"}
            ]}}
          ]
        }]
      }
    }
  }'
}

test_stable_redeployment_secrets() {
  local output_file permissions
  PLAN_DIRECTORY="$(mktemp -d)"
  output_file="$(mktemp)"
  export TF_VAR_application_jwt_secret='fixture-candidate-jwt'
  export TF_VAR_postgresql_application_password='fixture-candidate-postgres-app'
  export TF_VAR_application_admin_password='fixture-candidate-admin'
  export TF_VAR_postgresql_administrator_password='fixture-candidate-postgres-admin'
  terraform() { mock_terraform_secret_state; }

  prepare_stable_redeployment_secrets >"$output_file"
  permissions="$(stat -c '%a' "$REDEPLOY_SECRET_VAR_FILE")"
  [[ "$permissions" == 600 ]]
  jq -e '
    .application_jwt_secret == "fixture-stable-jwt"
    and .postgresql_application_password == "fixture-stable-postgres-app"
    and .application_admin_password == "fixture-stable-admin"
    and .postgresql_administrator_password == "fixture-stable-postgres-admin"
  ' "$REDEPLOY_SECRET_VAR_FILE" >/dev/null
  [[ "$(grep -c 'matches the deployed.*: false' "$output_file")" == 4 ]]
  if grep -q 'fixture-' "$output_file"; then return 1; fi
  rm -f -- "$output_file"
  rm -rf -- "$PLAN_DIRECTORY"
  REDEPLOY_SECRET_VAR_FILE=""
}

test_inconsistent_postgresql_secrets_refused() {
  local status=0
  PLAN_DIRECTORY="$(mktemp -d)"
  export TF_VAR_application_jwt_secret='fixture-candidate-jwt'
  export TF_VAR_postgresql_application_password='fixture-candidate-postgres-app'
  export TF_VAR_application_admin_password='fixture-candidate-admin'
  export TF_VAR_postgresql_administrator_password='fixture-candidate-postgres-admin'
  terraform() { mock_terraform_secret_state fixture-inconsistent-postgres-app; }

  if prepare_stable_redeployment_secrets >/dev/null; then
    status=1
  fi
  rm -rf -- "$PLAN_DIRECTORY"
  REDEPLOY_SECRET_VAR_FILE=""
  return "$status"
}

test_redeploy_plan_uses_private_secret_var_file() {
  local terraform_arguments
  PLAN_DIRECTORY="$(mktemp -d)"
  terraform_arguments="${PLAN_DIRECTORY}/terraform-arguments.txt"
  REDEPLOY_SECRET_VAR_FILE="${PLAN_DIRECTORY}/stable-redeployment-secrets.tfvars.json"
  jq -n '{
    application_jwt_secret: "fixture-stable-jwt",
    postgresql_application_password: "fixture-stable-postgres-app",
    application_admin_password: "fixture-stable-admin",
    postgresql_administrator_password: "fixture-stable-postgres-admin"
  }' >"$REDEPLOY_SECRET_VAR_FILE"
  chmod 600 "$REDEPLOY_SECRET_VAR_FILE"
  populate_digest_maps
  copy_digest_map CURRENT_APPLICATION_DIGESTS ROLLOUT_APPLICATION_DIGESTS
  terraform() {
    if [[ "$*" == *" plan "* ]]; then
      printf '%s\n' "$*" >"$terraform_arguments"
    elif [[ "$*" == *" show -json "* ]]; then
      jq -n '{resource_changes: []}'
    else
      return 1
    fi
  }

  create_safe_plan stable-secrets stable-secrets ROLLOUT_APPLICATION_DIGESTS \
    "$CURRENT_MIGRATION_DIGEST" "$ALL_ACTIVE_APPLICATIONS" pre-migration >/dev/null
  grep -Fq -- "-var-file=${REDEPLOY_SECRET_VAR_FILE}" "$terraform_arguments"
  if grep -q 'fixture-stable-' "$terraform_arguments"; then return 1; fi
  rm -rf -- "$PLAN_DIRECTORY"
  REDEPLOY_SECRET_VAR_FILE=""
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
  grep -A8 -- '- hold-aca-deployment:' "$CONTINUE_CONFIG" | grep -q -- '- aca-preflight'
  grep -A8 -- '- aca-preflight:' "$CONTINUE_CONFIG" | grep -q -- '- release-acr'
  if grep -A8 -- '- hold-aca-deployment:' "$CONTINUE_CONFIG" | grep -q 'context:'; then return 1; fi
}

test_terraform_apply_uses_saved_plan_without_automatic_approval_flag() {
  grep -q 'terraform -chdir="$ACA_TERRAFORM_DIRECTORY" apply \\' "$DEPLOY_SCRIPT"
  if grep -q -- 'apply -auto''-approve' "$DEPLOY_SCRIPT"; then return 1; fi
}

test_aca_preflight_read_only_and_gated() {
  grep -q 'aca_authenticate_with_circleci_oidc' "$ACA_PREFLIGHT"
  grep -q 'az acr repository list' "$ACA_PREFLIGHT"
  grep -q 'az storage blob show' "$ACA_PREFLIGHT"
  grep -q 'terraform -chdir="$ACA_TERRAFORM_DIRECTORY" state list' "$ACA_PREFLIGHT"
  grep -A8 -- '- plan-aca:' "$CONTINUE_CONFIG" | grep -q -- '- aca-preflight'
  grep -A8 -- '- aca-preflight:' "$CONTINUE_CONFIG" | grep -q -- '- release-acr'
  if grep -Eq 'terraform .* (apply|destroy)|storage blob (upload|delete|update|sync)|az containerapp (update|delete|create)' \
    "$ACA_PREFLIGHT"; then
    return 1
  fi
}

write_circleci_cli_mock() {
  local executable="$1"
  local task_agent_compatible="$2"

  printf '%s\n' \
    '#!/bin/bash' \
    'set -euo pipefail' \
    'if [[ -n "${MOCK_CIRCLECI_CALL_LOG:-}" ]]; then' \
    '  printf "%s:%s\\n" "${0##*/}" "$*" >>"$MOCK_CIRCLECI_CALL_LOG"' \
    'fi' \
    'if [[ "$*" == "run --help" ]]; then' \
    "  if [[ '$task_agent_compatible' == true ]]; then" \
    '    printf "%s\\n" "Available Commands:" "  deploy" "  oidc"' \
    '    exit 0' \
    '  fi' \
    '  printf "%s\\n" "Trigger, watch and cancel CI runs"' \
    '  exit 0' \
    'fi' \
    'if [[ "$*" == "run oidc get --help" ]]; then' \
    '  printf "%s\\n" "run oidc get --help must not be used as a capability probe" >&2' \
    '  exit 99' \
    'fi' \
    'if [[ "$*" == "run oidc get --claims {\"aud\":\"api://AzureADTokenExchange\"}" ]]; then' \
    '  if [[ -n "${MOCK_CIRCLECI_TMPDIR_LOG:-}" ]]; then' \
    '    printf "%s\\n" "$TMPDIR" >"$MOCK_CIRCLECI_TMPDIR_LOG"' \
    '  fi' \
    '  if [[ "${MOCK_OIDC_FAILURE:-false}" == true ]]; then exit 1; fi' \
    '  printf "%s\\n" "${MOCK_OIDC_TOKEN:-mock-oidc-token}"' \
    '  exit 0' \
    'fi' \
    'exit 1' >"$executable"
  chmod 700 "$executable"
}

test_circleci_agent_preferred_when_present() {
  local call_log mock_directory original_path resolved
  mock_directory="$(mktemp -d)"
  call_log="${mock_directory}/calls.log"
  original_path="$PATH"
  write_circleci_cli_mock "${mock_directory}/circleci-agent" false

  MOCK_CIRCLECI_CALL_LOG="$call_log"
  export MOCK_CIRCLECI_CALL_LOG
  PATH="$mock_directory"
  resolved="$(aca_resolve_circleci_environment_cli)"
  PATH="$original_path"
  [[ "$resolved" == "${mock_directory}/circleci-agent" ]]
  [[ ! -e "$call_log" ]]
}

test_circleci_agent_selected_over_local_cli() {
  local call_log mock_directory original_path resolved
  mock_directory="$(mktemp -d)"
  call_log="${mock_directory}/calls.log"
  original_path="$PATH"
  write_circleci_cli_mock "${mock_directory}/circleci" false
  write_circleci_cli_mock "${mock_directory}/circleci-agent" false

  MOCK_CIRCLECI_CALL_LOG="$call_log"
  export MOCK_CIRCLECI_CALL_LOG
  PATH="$mock_directory"
  resolved="$(aca_resolve_circleci_environment_cli)"
  PATH="$original_path"
  [[ "$resolved" == "${mock_directory}/circleci-agent" ]]
  [[ ! -e "$call_log" ]]
}

test_circleci_fallback_when_agent_unavailable() {
  local call_log mock_directory original_path resolved
  mock_directory="$(mktemp -d)"
  call_log="${mock_directory}/calls.log"
  original_path="$PATH"
  write_circleci_cli_mock "${mock_directory}/circleci" true

  MOCK_CIRCLECI_CALL_LOG="$call_log"
  export MOCK_CIRCLECI_CALL_LOG
  PATH="$mock_directory"
  resolved="$(aca_resolve_circleci_environment_cli)"
  PATH="$original_path"
  [[ "$resolved" == "${mock_directory}/circleci" ]]
  grep -Fqx 'circleci:run --help' "$call_log"
  if grep -q 'run oidc get --help' "$call_log"; then return 1; fi
}

test_circleci_environment_cli_resolution_fails_closed() {
  local mock_directory original_path status
  mock_directory="$(mktemp -d)"
  original_path="$PATH"
  write_circleci_cli_mock "${mock_directory}/circleci" false

  PATH="$mock_directory"
  status=0
  aca_resolve_circleci_environment_cli || status=$?
  PATH="$original_path"
  return "$status"
}

test_snap_circleci_is_never_selected_as_fallback() {
  aca_circleci_fallback_is_task_agent_compatible /snap/bin/circleci
}

test_circleci_preflight_diagnostics_report_paths_and_selection() {
  local mock_directory original_path output
  mock_directory="$(mktemp -d)"
  original_path="$PATH"
  write_circleci_cli_mock "${mock_directory}/circleci" false
  write_circleci_cli_mock "${mock_directory}/circleci-agent" false

  PATH="$mock_directory"
  output="$(aca_require_circleci_environment_cli)"
  PATH="$original_path"

  grep -Fqx "circleci path: ${mock_directory}/circleci" <<<"$output"
  grep -Fqx "circleci-agent path: ${mock_directory}/circleci-agent" <<<"$output"
  grep -Fqx "selected Environment CLI: ${mock_directory}/circleci-agent" <<<"$output"
}

test_oidc_authentication_uses_resolved_binary_without_logging_token() {
  local call_log mock_directory oidc_tmpdir oidc_tmpdir_log oidc_token
  local original_directory original_path output
  mock_directory="$(mktemp -d)"
  call_log="${mock_directory}/calls.log"
  oidc_tmpdir_log="${mock_directory}/oidc-tmpdir.log"
  oidc_token='mock-sensitive-oidc-token'
  original_directory="$PWD"
  original_path="$PATH"
  write_circleci_cli_mock "${mock_directory}/circleci" false
  write_circleci_cli_mock "${mock_directory}/circleci-agent" true

  aca_validate_circleci_oidc_token_claims() {
    [[ "$1" == "$oidc_token" ]]
  }
  az() {
    case "${1:-} ${2:-}" in
      "login --service-principal"|"account set") ;;
      "account show")
        if [[ "$*" == *"--query id"* ]]; then
          printf '%s\n' "$AZURE_SUBSCRIPTION_ID"
        elif [[ "$*" == *"--query tenantId"* ]]; then
          printf '%s\n' "$AZURE_TENANT_ID"
        else
          return 1
        fi
        ;;
      *) return 1 ;;
    esac
  }

  CIRCLE_BRANCH=master
  CIRCLE_PROJECT_USERNAME="$ACA_EXPECTED_CIRCLECI_PROJECT_USERNAME"
  CIRCLE_PROJECT_REPONAME="$ACA_EXPECTED_CIRCLECI_PROJECT_REPONAME"
  AZURE_CLIENT_ID=mock-client-id
  AZURE_TENANT_ID=mock-tenant-id
  AZURE_SUBSCRIPTION_ID=mock-subscription-id
  MOCK_CIRCLECI_CALL_LOG="$call_log"
  MOCK_CIRCLECI_TMPDIR_LOG="$oidc_tmpdir_log"
  MOCK_OIDC_TOKEN="$oidc_token"
  export MOCK_CIRCLECI_CALL_LOG MOCK_CIRCLECI_TMPDIR_LOG MOCK_OIDC_TOKEN
  PATH="$mock_directory:$original_path"
  TMPDIR=/tmp/task-agent-subcommands
  export TMPDIR
  cd "$mock_directory"
  output="$(aca_authenticate_with_circleci_oidc 2>&1)"

  cd "$original_directory"
  PATH="$original_path"
  oidc_tmpdir="$(<"$oidc_tmpdir_log")"
  grep -Fqx 'circleci-agent:run oidc get --claims {"aud":"api://AzureADTokenExchange"}' \
    "$call_log"
  if grep -q '^circleci:run oidc get --claims' "$call_log"; then return 1; fi
  [[ "$oidc_tmpdir" == "${mock_directory}/.circleci-oidc-tmp."* ]]
  [[ ! -e "$oidc_tmpdir" ]]
  [[ "$output" != *"$oidc_token"* ]]
}

test_oidc_generation_failure_fails_closed() {
  local call_log mock_directory oidc_tmpdir oidc_tmpdir_log original_directory
  local original_path output status
  mock_directory="$(mktemp -d)"
  call_log="${mock_directory}/calls.log"
  oidc_tmpdir_log="${mock_directory}/oidc-tmpdir.log"
  original_directory="$PWD"
  original_path="$PATH"
  write_circleci_cli_mock "${mock_directory}/circleci-agent" false

  aca_validate_circleci_oidc_token_claims() {
    return 1
  }
  az() {
    printf '%s\n' "$*" >>"$call_log"
  }

  CIRCLE_BRANCH=master
  CIRCLE_PROJECT_USERNAME="$ACA_EXPECTED_CIRCLECI_PROJECT_USERNAME"
  CIRCLE_PROJECT_REPONAME="$ACA_EXPECTED_CIRCLECI_PROJECT_REPONAME"
  AZURE_CLIENT_ID=mock-client-id
  AZURE_TENANT_ID=mock-tenant-id
  AZURE_SUBSCRIPTION_ID=mock-subscription-id
  MOCK_CIRCLECI_CALL_LOG="$call_log"
  MOCK_CIRCLECI_TMPDIR_LOG="$oidc_tmpdir_log"
  MOCK_OIDC_FAILURE=true
  export MOCK_CIRCLECI_CALL_LOG MOCK_CIRCLECI_TMPDIR_LOG MOCK_OIDC_FAILURE
  PATH="$mock_directory:$original_path"
  TMPDIR=/tmp/task-agent-subcommands
  export TMPDIR
  cd "$mock_directory"
  status=0
  output="$(aca_authenticate_with_circleci_oidc 2>&1)" || status=$?
  cd "$original_directory"
  PATH="$original_path"

  oidc_tmpdir="$(<"$oidc_tmpdir_log")"
  [[ "$status" -ne 0 ]]
  grep -Fqx 'circleci-agent:run oidc get --claims {"aud":"api://AzureADTokenExchange"}' \
    "$call_log"
  if grep -q '^login ' "$call_log"; then return 1; fi
  [[ "$oidc_tmpdir" == "${mock_directory}/.circleci-oidc-tmp."* ]]
  [[ ! -e "$oidc_tmpdir" ]]
  [[ "$output" == *"CircleCI failed to issue a custom-audience OIDC token."* ]]
}

test_circleci_environment_cli_not_overwritten() {
  grep -q 'aca_require_circleci_environment_cli' "$CONTINUE_CONFIG"
  grep -q 'aca_require_circleci_environment_cli' "$ROOT_CONFIG"
  if grep -Eq 'CircleCI-Public/circleci-cli|circleci_archive|install .*/circleci' \
    "$CONTINUE_CONFIG" "$ROOT_CONFIG"; then
    return 1
  fi
}

make_test_oidc_token() {
  local audience="$1"
  local vcs_origin="$2"
  local vcs_ref="$3"

  python3 - "$audience" "$vcs_origin" "$vcs_ref" <<'PY'
import base64
import json
import sys

def encode(value):
    raw = json.dumps(value, separators=(",", ":")).encode()
    return base64.urlsafe_b64encode(raw).rstrip(b"=").decode()

header = {"alg": "none", "typ": "JWT"}
payload = {
    "aud": sys.argv[1],
    "oidc.circleci.com/vcs-origin": sys.argv[2],
    "oidc.circleci.com/vcs-ref": sys.argv[3],
}
print(f"{encode(header)}.{encode(payload)}.test-signature")
PY
}

test_oidc_claims_validation() {
  local token
  token="$(make_test_oidc_token \
    'api://AzureADTokenExchange' \
    "$ACA_EXPECTED_CIRCLECI_VCS_ORIGIN" \
    "$ACA_EXPECTED_CIRCLECI_VCS_REF")"

  aca_validate_circleci_oidc_token_claims "$token"
}

test_oidc_wrong_branch_rejected() {
  local token
  token="$(make_test_oidc_token \
    'api://AzureADTokenExchange' \
    "$ACA_EXPECTED_CIRCLECI_VCS_ORIGIN" \
    'refs/heads/untrusted')"

  aca_validate_circleci_oidc_token_claims "$token"
}

test_oidc_wrong_audience_rejected() {
  local token
  token="$(make_test_oidc_token \
    'an-unexpected-audience' \
    "$ACA_EXPECTED_CIRCLECI_VCS_ORIGIN" \
    "$ACA_EXPECTED_CIRCLECI_VCS_REF")"

  aca_validate_circleci_oidc_token_claims "$token"
}

test_oidc_wrong_repository_rejected() {
  local token
  token="$(make_test_oidc_token \
    'api://AzureADTokenExchange' \
    'github.com/untrusted/repository' \
    "$ACA_EXPECTED_CIRCLECI_VCS_REF")"

  aca_validate_circleci_oidc_token_claims "$token"
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
assert_succeeds "initial rollout retains every progressive activation set and executes migrations" test_initial_rollout
assert_succeeds "changed migration digest executes before redeploy and all apps remain active" test_redeploy_migration_gate
assert_succeeds "multiline Azure CLI revision details are parsed exactly" test_multiline_revision_parsing
assert_succeeds "exact ready revision with Healthy and Provisioned passes" test_revision_health_condition healthy
assert_fails "wrong latest-ready revision does not pass" test_revision_health_condition wrong-ready
assert_fails "Unhealthy expected revision stops release" test_revision_health_condition unhealthy
assert_fails "Failed provisioning stops release" test_revision_health_condition failed
assert_fails "non-Provisioned expected revision does not pass" test_revision_health_condition non-provisioned
assert_succeeds "post-deployment validation retains exactly both public HTTP checks" test_post_deployment_http_checks_only
assert_succeeds "deployment-time container exec check is absent" test_no_deployment_exec_check_remains
assert_succeeds "zero-change validated plan skips Terraform apply" test_zero_change_plan_skips_apply
assert_succeeds "changed validated plan applies the exact saved plan" test_changed_plan_applies_exact_saved_plan
assert_succeeds "business wave uses one saved plan, at most one apply, and verifies all five apps" test_business_wave_single_saved_plan_apply
assert_succeeds "zero-change business wave skips apply and revision waits" test_business_wave_zero_change_skips_apply
assert_succeeds "partially changed business wave waits only for changed apps" test_business_wave_partial_change_waits_only_changed
assert_fails "one failed business revision fails the complete wave" test_business_wave_one_failed_revision_fails_wave
assert_succeeds "Terraform apply remains single-process and foreground" test_no_concurrent_terraform_apply
assert_succeeds "timing diagnostics expose no command arguments" test_timing_diagnostics_exclude_arguments
assert_succeeds "normal redeploy with unchanged applications passes pre-migration" test_normal_redeploy_no_changes
assert_succeeds "application image update is allowed only after migration" test_application_image_update_after_migration_allowed
assert_succeeds "business wave allows an intended business app update" test_business_wave_intended_update_allowed
assert_fails "business wave refuses an unexpected client update" test_business_wave_unexpected_client_change_refused
assert_fails "business wave refuses an unexpected foundation update" test_business_wave_foundation_update_refused
assert_succeeds "migration-job image update is allowed before migration" test_migration_job_image_update_before_migration_allowed
assert_fails "application image update before migration is refused" test_pre_migration_attribute_refusal image
assert_fails "application scaling update before migration is refused" test_pre_migration_attribute_refusal scaling
assert_fails "application ingress update before migration is refused" test_pre_migration_attribute_refusal ingress
assert_fails "application probe update before migration is refused" test_pre_migration_attribute_refusal probe
assert_fails "uncontrolled application secret rotation is refused" test_pre_migration_attribute_refusal secret
assert_fails "Terraform delete action is refused" test_plan_delete_refusal
assert_fails "Terraform delete/create replacement is refused" test_plan_replacement_refusal
assert_fails "unexpected Terraform resource creation is refused" test_unexpected_create_refusal
assert_succeeds "sensitive plan value is absent from summary" test_plan_sensitive_value_not_logged
assert_succeeds "all six app updates and the migration job are classified" test_all_seven_updates_are_classified
assert_succeeds "routine redeploy preserves consistent healthy-release secrets" test_stable_redeployment_secrets
assert_succeeds "inconsistent PostgreSQL app and migration secrets are refused" test_inconsistent_postgresql_secrets_refused
assert_succeeds "redeploy plans use the private secret var file without argv exposure" test_redeploy_plan_uses_private_secret_var_file
assert_succeeds "Cosmos URI is derived, injected, sensitive, and not context-driven" test_cosmos_derivation
assert_succeeds "OIDC state audit is read-only and does not infer write" test_oidc_audit_read_only
assert_succeeds "CircleCI approval and stable serial group block concurrent deployment" test_circleci_serial_gate
assert_succeeds "Terraform applies saved plans without automatic approval flag" test_terraform_apply_uses_saved_plan_without_automatic_approval_flag
assert_succeeds "ACA preflight is read-only and gates plan-aca" test_aca_preflight_read_only_and_gated
assert_succeeds "executable circleci-agent is selected without an OIDC help probe" test_circleci_agent_preferred_when_present
assert_succeeds "circleci-agent wins over the unrelated local circleci CLI" test_circleci_agent_selected_over_local_cli
assert_succeeds "circleci is selected when the agent command is unavailable" test_circleci_fallback_when_agent_unavailable
assert_fails "CircleCI OIDC resolution fails closed without a task-agent-compatible CLI" test_circleci_environment_cli_resolution_fails_closed
assert_fails "/snap/bin/circleci is never accepted as an environment CLI fallback" test_snap_circleci_is_never_selected_as_fallback
assert_succeeds "CircleCI preflight reports both paths and the selected Environment CLI" test_circleci_preflight_diagnostics_report_paths_and_selection
assert_succeeds "OIDC generation uses the resolved binary without logging the token" test_oidc_authentication_uses_resolved_binary_without_logging_token
assert_succeeds "OIDC token generation failure stops before Azure login" test_oidc_generation_failure_fails_closed
assert_succeeds "CircleCI environment CLI is never overwritten" test_circleci_environment_cli_not_overwritten
assert_succeeds "CircleCI OIDC claims pass without readonly reassignment" test_oidc_claims_validation
assert_fails "CircleCI OIDC token from an unexpected branch is rejected" test_oidc_wrong_branch_rejected
assert_fails "CircleCI OIDC token with an unexpected audience is rejected" test_oidc_wrong_audience_rejected
assert_fails "CircleCI OIDC token from an unexpected repository is rejected" test_oidc_wrong_repository_rejected

printf 'ACA deployment mock suite passed: %s checks.\n' "$TEST_COUNT"
