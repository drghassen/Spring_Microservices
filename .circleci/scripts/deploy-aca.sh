#!/usr/bin/env bash

set -euo pipefail

# shellcheck source-path=SCRIPTDIR
# shellcheck source=lib/aca-deployment.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/aca-deployment.sh"

readonly MIGRATIONS_POLL_INTERVAL_SECONDS="${MIGRATIONS_POLL_INTERVAL_SECONDS:-10}"
readonly MIGRATIONS_TIMEOUT_SECONDS="${MIGRATIONS_TIMEOUT_SECONDS:-900}"
readonly APP_HEALTH_POLL_INTERVAL_SECONDS="${APP_HEALTH_POLL_INTERVAL_SECONDS:-10}"
readonly APP_HEALTH_TIMEOUT_SECONDS="${APP_HEALTH_TIMEOUT_SECONDS:-900}"

readonly NO_ACTIVE_APPLICATIONS='[]'
readonly CONFIG_ACTIVE_APPLICATIONS='["config-server"]'
readonly DISCOVERY_ACTIVE_APPLICATIONS='["config-server","discovery-service"]'
readonly GATEWAY_ACTIVE_APPLICATIONS='["config-server","discovery-service","gateway"]'
readonly GAMES_ACTIVE_APPLICATIONS='["config-server","discovery-service","gateway","games-service"]'
readonly LIBRARY_ACTIVE_APPLICATIONS='["config-server","discovery-service","gateway","games-service","library-service"]'
readonly ORDER_ACTIVE_APPLICATIONS='["config-server","discovery-service","gateway","games-service","library-service","order-service"]'
readonly PAYMENT_ACTIVE_APPLICATIONS='["config-server","discovery-service","gateway","games-service","library-service","order-service","payment-service"]'
readonly BUSINESS_ACTIVE_APPLICATIONS='["config-server","discovery-service","gateway","games-service","library-service","order-service","payment-service","user-service"]'
readonly ALL_ACTIVE_APPLICATIONS='["client","config-server","discovery-service","gateway","games-service","library-service","order-service","payment-service","user-service"]'

readonly ACA_REQUIRED_STATE_ADDRESSES=(
  'data.azurerm_container_registry.current'
  'data.azurerm_resource_group.current'
  'module.data.azurerm_cosmosdb_account.mongodb'
  'module.data.azurerm_cosmosdb_mongo_collection.library'
  'module.data.azurerm_cosmosdb_mongo_collection.users'
  'module.data.azurerm_cosmosdb_mongo_database.library'
  'module.data.azurerm_cosmosdb_mongo_database.users'
  'module.data.azurerm_private_dns_zone.postgresql'
  'module.data.azurerm_private_dns_zone_virtual_network_link.postgresql'
  'module.data.azurerm_postgresql_flexible_server.this'
  'module.data.azurerm_postgresql_flexible_server_database.steam'
  'module.foundation.azurerm_container_app_environment.this'
  'module.foundation.azurerm_log_analytics_workspace.this'
  'module.identities.azurerm_user_assigned_identity.apps'
  'module.identities.azurerm_role_assignment.acr_pull'
  'module.network.azurerm_subnet.aca_infrastructure'
  'module.network.azurerm_subnet.postgresql'
  'module.network.azurerm_subnet.private_endpoints'
  'module.network.azurerm_virtual_network.this'
)

declare -A DESIRED_APPLICATION_DIGESTS=()
declare -A CURRENT_APPLICATION_DIGESTS=()
declare -A ROLLOUT_APPLICATION_DIGESTS=()
declare -A DEPLOYED_REVISIONS=()
declare -a AZURE_APPLICATION_NAMES=()
declare -a STATE_RESOURCE_ADDRESSES=()

ACR_LOGIN_SERVER=""
DESIRED_MIGRATION_DIGEST=""
CURRENT_MIGRATION_DIGEST=""
DETECTED_RELEASE_MODE=""
AZURE_MIGRATION_JOB_EXISTS=0
PLAN_DIRECTORY=""
LAST_PLAN_FILE=""
LAST_PLAN_ADD_COUNT=0
LAST_PLAN_CHANGE_COUNT=0
LAST_PLAN_DESTROY_COUNT=0
REDEPLOY_SECRET_VAR_FILE=""

validate_positive_integer() {
  local variable_name="$1"
  local value="${!variable_name}"

  [[ "$value" =~ ^[1-9][0-9]*$ ]] || {
    printf '%s must be a positive integer.\n' "$variable_name" >&2
    exit 1
  }
}

validate_release_inputs() {
  local required_variable
  local required_command

  for required_variable in \
    AZURE_CLIENT_ID \
    AZURE_TENANT_ID \
    AZURE_SUBSCRIPTION_ID \
    IMAGE_TAG \
    TF_VAR_postgresql_administrator_login \
    TF_VAR_postgresql_administrator_password \
    TF_VAR_postgresql_application_password \
    TF_VAR_application_jwt_secret \
    TF_VAR_application_admin_password; do
    aca_require_environment_variable "$required_variable"
  done

  for required_command in az circleci curl jq python3 terraform; do
    aca_require_command "$required_command"
  done

  [[ "$IMAGE_TAG" =~ ^build-[0-9]+$ && "$IMAGE_TAG" != "build-31" ]] || {
    echo "IMAGE_TAG must be an immutable build-<number> tag other than build-31." >&2
    exit 1
  }
  [[ "${TF_VAR_postgresql_administrator_login:-}" == "ghassenpg" ]] || {
    echo "TF_VAR_postgresql_administrator_login must be ghassenpg for the existing PostgreSQL server." >&2
    exit 1
  }

  validate_positive_integer MIGRATIONS_POLL_INTERVAL_SECONDS
  validate_positive_integer MIGRATIONS_TIMEOUT_SECONDS
  validate_positive_integer APP_HEALTH_POLL_INTERVAL_SECONDS
  validate_positive_integer APP_HEALTH_TIMEOUT_SECONDS
}

resolve_acr_digest() {
  local repository="$1"
  local tag="$2"
  local digest

  digest="$(az acr repository show --name "$ACA_ACR_NAME" --image "${repository}:${tag}" \
    --query digest --output tsv --only-show-errors)"
  [[ "$digest" =~ ^sha256:[0-9a-f]{64}$ ]] || {
    printf 'ACR did not return a valid digest for %s:%s.\n' "$repository" "$tag" >&2
    exit 1
  }
  printf '%s\n' "$digest"
}

verify_release_images() {
  local application

  ACR_LOGIN_SERVER="$(az acr show --name "$ACA_ACR_NAME" \
    --resource-group "$ACA_RESOURCE_GROUP_NAME" --query loginServer \
    --output tsv --only-show-errors)"
  [[ -n "$ACR_LOGIN_SERVER" ]] || {
    echo "Azure did not return the ACR login server." >&2
    exit 1
  }

  for application in "${ACA_APPLICATIONS[@]}"; do
    DESIRED_APPLICATION_DIGESTS["$application"]="$(resolve_acr_digest "$application" "$IMAGE_TAG")"
    printf 'Verified immutable ACR image: %s:%s\n' "$application" "$IMAGE_TAG"
  done
  DESIRED_MIGRATION_DIGEST="$(resolve_acr_digest database-migrations "$IMAGE_TAG")"
  printf 'Verified immutable ACR image: database-migrations:%s\n' "$IMAGE_TAG"
}

initialize_terraform() {
  terraform -chdir="$ACA_TERRAFORM_DIRECTORY" init -input=false \
    -backend-config="resource_group_name=${ACA_TF_STATE_RESOURCE_GROUP_NAME}" \
    -backend-config="storage_account_name=${ACA_TF_STATE_STORAGE_ACCOUNT_NAME}" \
    -backend-config="container_name=${ACA_TF_STATE_CONTAINER_NAME}" \
    -backend-config="key=${ACA_TF_STATE_KEY}" \
    -backend-config="use_azuread_auth=true" \
    -backend-config="use_cli=true" >/dev/null
  echo "Terraform backend initialized."
}

load_release_inventories() {
  local applications_file="${PLAN_DIRECTORY}/azure-applications.txt"
  local jobs_file="${PLAN_DIRECTORY}/azure-jobs.txt"
  local state_file="${PLAN_DIRECTORY}/terraform-state-addresses.txt"

  az containerapp list --resource-group "$ACA_RESOURCE_GROUP_NAME" \
    --query '[].name' --output tsv --only-show-errors >"$applications_file" || {
    echo "Unable to inventory Azure Container Apps; release mode cannot be determined safely." >&2
    exit 1
  }
  az containerapp job list --resource-group "$ACA_RESOURCE_GROUP_NAME" \
    --query '[].name' --output tsv --only-show-errors >"$jobs_file" || {
    echo "Unable to inventory Azure Container Apps Jobs; release mode cannot be determined safely." >&2
    exit 1
  }
  terraform -chdir="$ACA_TERRAFORM_DIRECTORY" state list >"$state_file" || {
    echo "Unable to read Terraform state addresses; release mode cannot be determined safely." >&2
    exit 1
  }

  mapfile -t AZURE_APPLICATION_NAMES <"$applications_file"
  mapfile -t STATE_RESOURCE_ADDRESSES <"$state_file"
  if grep -Fxq "$ACA_MIGRATIONS_JOB_NAME" "$jobs_file"; then
    AZURE_MIGRATION_JOB_EXISTS=1
  else
    AZURE_MIGRATION_JOB_EXISTS=0
  fi
}

array_contains() {
  local needle="$1"
  shift
  local value
  for value in "$@"; do
    [[ "$value" == "$needle" ]] && return 0
  done
  return 1
}

validate_foundation_state() {
  local address
  local -a missing_addresses=()
  for address in "${ACA_REQUIRED_STATE_ADDRESSES[@]}"; do
    if ! array_contains "$address" "${STATE_RESOURCE_ADDRESSES[@]}"; then
      missing_addresses+=("$address")
    fi
  done
  if (( ${#missing_addresses[@]} != 0 )); then
    echo "Terraform state is missing required foundation resources; release refused." >&2
    printf 'Missing state address: %s\n' "${missing_addresses[@]}" >&2
    exit 1
  fi
}

detect_release_mode() {
  local application
  local address
  local azure_application_count=0
  local state_application_count=0
  local state_migration_job_exists=0
  local -a missing_azure_applications=()
  local -a missing_state_applications=()

  validate_foundation_state
  for application in "${ACA_APPLICATIONS[@]}"; do
    if array_contains "$application" "${AZURE_APPLICATION_NAMES[@]}"; then
      azure_application_count=$((azure_application_count + 1))
    else
      missing_azure_applications+=("$application")
    fi
    address="module.apps.azurerm_container_app.this[\"${application}\"]"
    if array_contains "$address" "${STATE_RESOURCE_ADDRESSES[@]}"; then
      state_application_count=$((state_application_count + 1))
    else
      missing_state_applications+=("$application")
    fi
  done
  if array_contains 'module.apps.azurerm_container_app_job.database_migrations' \
    "${STATE_RESOURCE_ADDRESSES[@]}"; then
    state_migration_job_exists=1
  fi

  if ((azure_application_count > 0 && azure_application_count < ${#ACA_APPLICATIONS[@]})); then
    printf 'Azure contains a partial ACA release (%s/%s applications); release refused.\n' \
      "$azure_application_count" "${#ACA_APPLICATIONS[@]}" >&2
    printf 'Missing Azure application: %s\n' "${missing_azure_applications[@]}" >&2
    exit 1
  fi
  if ((state_application_count > 0 && state_application_count < ${#ACA_APPLICATIONS[@]})); then
    printf 'Terraform state contains a partial ACA release (%s/%s applications); release refused.\n' \
      "$state_application_count" "${#ACA_APPLICATIONS[@]}" >&2
    printf 'Missing state application: %s\n' "${missing_state_applications[@]}" >&2
    exit 1
  fi

  if ((azure_application_count == 0 && AZURE_MIGRATION_JOB_EXISTS == 0 && \
    state_application_count == 0 && state_migration_job_exists == 0)); then
    DETECTED_RELEASE_MODE="initial"
  elif ((azure_application_count == ${#ACA_APPLICATIONS[@]} && AZURE_MIGRATION_JOB_EXISTS == 1 && \
    state_application_count == ${#ACA_APPLICATIONS[@]} && state_migration_job_exists == 1)); then
    DETECTED_RELEASE_MODE="redeploy"
  else
    printf 'Azure/Terraform ACA inventory is inconsistent (Azure apps=%s, state apps=%s, Azure job=%s, state job=%s); release refused.\n' \
      "$azure_application_count" "$state_application_count" \
      "$AZURE_MIGRATION_JOB_EXISTS" "$state_migration_job_exists" >&2
    exit 1
  fi
  printf 'ACA release mode detected automatically: %s\n' "$DETECTED_RELEASE_MODE"
}

digest_from_image_reference() {
  local repository="$1"
  local image_reference="$2"
  local digest_prefix="${ACR_LOGIN_SERVER}/${repository}@"
  local tag_prefix="${ACR_LOGIN_SERVER}/${repository}:"
  local tag
  if [[ "$image_reference" == "${digest_prefix}"* ]]; then
    image_reference="${image_reference#"$digest_prefix"}"
    [[ "$image_reference" =~ ^sha256:[0-9a-f]{64}$ ]] || {
      printf 'Current image for %s has an invalid digest.\n' "$repository" >&2
      exit 1
    }
    printf '%s\n' "$image_reference"
    return
  fi
  if [[ "$image_reference" == "${tag_prefix}"* ]]; then
    tag="${image_reference#"$tag_prefix"}"
    [[ "$tag" =~ ^build-[0-9]+$ ]] || {
      printf 'Current image for %s does not use an approved immutable build tag.\n' "$repository" >&2
      exit 1
    }
    resolve_acr_digest "$repository" "$tag"
    return
  fi
  printf 'Current image for %s is outside the expected ACR repository.\n' "$repository" >&2
  exit 1
}

parse_exact_required_tsv_lines() {
  local expected_count="$1" tsv_output="$2" destination_name="$3" value
  local -n destination="$destination_name"
  destination=()
  [[ -n "$tsv_output" ]] || return 1
  mapfile -t destination <<<"$tsv_output"
  (( ${#destination[@]} == expected_count )) || return 1
  for value in "${destination[@]}"; do
    [[ -n "$value" && "$value" != "null" ]] || return 1
  done
}

load_current_healthy_release() {
  local application latest_revision ready_revision health_state provisioning_state image_reference
  local revision_names_output revision_details_output
  local -a revision_names=() revision_details=()
  for application in "${ACA_APPLICATIONS[@]}"; do
    if ! revision_names_output="$(az containerapp show \
      --name "$application" --resource-group "$ACA_RESOURCE_GROUP_NAME" \
      --query '[properties.latestRevisionName, properties.latestReadyRevisionName]' \
      --output tsv --only-show-errors)"; then
      printf 'Unable to read revision names for application %s; redeployment refused.\n' \
        "$application" >&2
      exit 1
    fi
    if ! parse_exact_required_tsv_lines 2 "$revision_names_output" revision_names; then
      printf 'Azure returned malformed revision names for application %s; redeployment refused.\n' \
        "$application" >&2
      exit 1
    fi
    latest_revision="${revision_names[0]}"
    ready_revision="${revision_names[1]}"
    [[ -n "$latest_revision" && "$latest_revision" == "$ready_revision" ]] || {
      printf 'Application %s has no healthy latest ready revision; redeployment refused.\n' "$application" >&2
      exit 1
    }
    if ! revision_details_output="$(az containerapp revision show \
      --name "$application" --resource-group "$ACA_RESOURCE_GROUP_NAME" \
      --revision "$latest_revision" \
      --query '[properties.healthState, properties.provisioningState, properties.template.containers[0].image]' \
      --output tsv --only-show-errors)"; then
      printf 'Unable to read latest revision details for application %s; redeployment refused.\n' \
        "$application" >&2
      exit 1
    fi
    if ! parse_exact_required_tsv_lines 3 "$revision_details_output" revision_details; then
      printf 'Azure returned malformed latest revision details for application %s; redeployment refused.\n' \
        "$application" >&2
      exit 1
    fi
    health_state="${revision_details[0]}"
    provisioning_state="${revision_details[1]}"
    image_reference="${revision_details[2]}"
    [[ "$health_state" == "Healthy" && "$provisioning_state" == "Provisioned" ]] || {
      printf 'Application %s latest revision is not healthy; redeployment refused.\n' "$application" >&2
      exit 1
    }
    # The associative map is later selected by name through a nameref.
    # shellcheck disable=SC2034
    CURRENT_APPLICATION_DIGESTS["$application"]="$(digest_from_image_reference "$application" "$image_reference")"
  done
  image_reference="$(az containerapp job show --name "$ACA_MIGRATIONS_JOB_NAME" \
    --resource-group "$ACA_RESOURCE_GROUP_NAME" \
    --query 'properties.template.containers[0].image' --output tsv --only-show-errors)"
  CURRENT_MIGRATION_DIGEST="$(digest_from_image_reference database-migrations "$image_reference")"
  echo "Existing healthy ACA release and migration job references verified."
}

copy_digest_map() {
  local source_name="$1" destination_name="$2" application
  local -n source_map="$source_name"
  local -n destination_map="$destination_name"
  for application in "${ACA_APPLICATIONS[@]}"; do
    # ShellCheck cannot follow writes through this destination nameref.
    # shellcheck disable=SC2034
    destination_map["$application"]="${source_map[$application]}"
  done
}

digests_as_json() {
  local map_name="$1" application json='{}'
  local -n digest_map="$map_name"
  for application in "${ACA_APPLICATIONS[@]}"; do
    [[ "${digest_map[$application]:-}" =~ ^sha256:[0-9a-f]{64}$ ]] || {
      printf 'Missing valid digest for %s.\n' "$application" >&2
      exit 1
    }
    json="$(jq -c --arg key "$application" --arg value "${digest_map[$application]}" \
      '. + {($key): $value}' <<<"$json")"
  done
  printf '%s\n' "$json"
}

print_pre_migration_plan_changes() {
  local plan_json="$1"

  printf 'Pre-migration Terraform changes:\n' >&2
  jq -r '
    def path_text:
      reduce .[] as $part ("";
        . + if ($part | type) == "number" then
          "[\($part)]"
        elif . == "" then
          $part
        else
          ".\($part)"
        end
      );
    def changed_paths($before; $after; $before_sensitive; $after_sensitive; $path):
      if $before == $after then
        empty
      elif $before_sensitive == true or $after_sensitive == true then
        $path
      elif ($before | type) == "object" and ($after | type) == "object" then
        (($before | keys_unsorted) + ($after | keys_unsorted) | unique[]) as $key
        | changed_paths(
            $before[$key];
            $after[$key];
            $before_sensitive[$key];
            $after_sensitive[$key];
            $path + [$key]
          )
      elif ($before | type) == "array" and ($after | type) == "array" then
        range(0; [($before | length), ($after | length)] | max) as $index
        | changed_paths(
            $before[$index];
            $after[$index];
            $before_sensitive[$index];
            $after_sensitive[$index];
            $path + [$index]
          )
      else
        $path
      end;
    [.resource_changes[]? | select(.change.actions != ["no-op"])]
    | sort_by(.address)[]
    | . as $resource
    | [changed_paths(
        $resource.change.before;
        $resource.change.after;
        $resource.change.before_sensitive;
        $resource.change.after_sensitive;
        []
      ) | path_text] as $paths
    | "\n- \($resource.address)\n  actions: \($resource.change.actions | tojson)\n  changed paths: \($paths | unique | join(", "))"
  ' "$plan_json" >&2
}

inspect_plan_json() {
  local plan_json="$1" phase_name="$2" allowed_create_scope="$3"
  local plan_summary replacement_count unexpected_create_count unexpected_app_change_count
  if ! plan_summary="$(jq -er ' [.resource_changes[]?.change.actions] as $actions | [
      ([$actions[] | select(index("create") != null)] | length),
      ([$actions[] | select(index("update") != null)] | length),
      ([$actions[] | select(index("delete") != null)] | length),
      ([$actions[] | select(index("delete") != null and index("create") != null)] | length)
    ] | @tsv' "$plan_json" 2>/dev/null)"; then
    echo "Unable to parse the Terraform plan summary safely; operation refused." >&2
    return 1
  fi
  IFS=$'\t' read -r LAST_PLAN_ADD_COUNT LAST_PLAN_CHANGE_COUNT \
    LAST_PLAN_DESTROY_COUNT replacement_count <<<"$plan_summary"
  if [[ ! "$LAST_PLAN_ADD_COUNT" =~ ^[0-9]+$ || ! "$LAST_PLAN_CHANGE_COUNT" =~ ^[0-9]+$ || \
    ! "$LAST_PLAN_DESTROY_COUNT" =~ ^[0-9]+$ || ! "$replacement_count" =~ ^[0-9]+$ ]]; then
    echo "Terraform returned invalid plan action counts; operation refused." >&2
    return 1
  fi
  printf 'Terraform plan summary for %s: add=%s change=%s destroy=%s\n' \
    "$phase_name" "$LAST_PLAN_ADD_COUNT" "$LAST_PLAN_CHANGE_COUNT" "$LAST_PLAN_DESTROY_COUNT"
  if ((LAST_PLAN_DESTROY_COUNT != 0 || replacement_count != 0)); then
    printf 'Delete or delete/create action detected in phase %s; operation refused.\n' "$phase_name" >&2
    return 1
  fi
  if ! unexpected_create_count="$(jq -er --arg scope "$allowed_create_scope" '[
    .resource_changes[]? | select(.change.actions | index("create") != null)
    | select($scope != "initial-apps-job" or (
        ((.address | test("^module[.]apps[.]azurerm_container_app[.]this\\[")) | not)
        and .address != "module.apps.azurerm_container_app_job.database_migrations"
      ))] | length' "$plan_json" 2>/dev/null)"; then
    echo "Unable to inspect Terraform resource creations safely; operation refused." >&2
    return 1
  fi
  if ((unexpected_create_count != 0)); then
    printf 'Unexpected resource creation detected in phase %s; foundation recreation is refused.\n' \
      "$phase_name" >&2
    return 1
  fi

  if [[ "$allowed_create_scope" == "pre-migration" ]]; then
    if ! unexpected_app_change_count="$(jq -er '[
      .resource_changes[]?
      | select(.address | test("^module[.]apps[.]azurerm_container_app[.]this\\["))
      | select(.change.actions != ["no-op"])
    ] | length' "$plan_json" 2>/dev/null)"; then
      echo "Unable to inspect pre-migration Container App changes safely; operation refused." >&2
      return 1
    fi
    if ((unexpected_app_change_count != 0)); then
      print_pre_migration_plan_changes "$plan_json"
      printf 'Container App change detected before migration in phase %s; operation refused.\n' \
        "$phase_name" >&2
      return 1
    fi
  fi
}

create_safe_plan() {
  local phase_slug="$1" phase_name="$2" digest_map_name="$3"
  local migration_digest="$4" active_applications="$5" allowed_create_scope="$6"
  local application_digests_json plan_json plan_log plan_exit
  local -a secret_var_file_argument=()
  application_digests_json="$(digests_as_json "$digest_map_name")"
  LAST_PLAN_FILE="${PLAN_DIRECTORY}/${phase_slug}.tfplan"
  plan_json="${PLAN_DIRECTORY}/${phase_slug}.json"
  plan_log="${PLAN_DIRECTORY}/${phase_slug}.plan.log"
  if [[ -n "$REDEPLOY_SECRET_VAR_FILE" ]]; then
    [[ -s "$REDEPLOY_SECRET_VAR_FILE" ]] || {
      echo "Stable redeployment secret inputs are unavailable." >&2
      exit 1
    }
    secret_var_file_argument=(-var-file="$REDEPLOY_SECRET_VAR_FILE")
  fi
  printf 'Planning ACA phase: %s\n' "$phase_name"
  set +e
  terraform -chdir="$ACA_TERRAFORM_DIRECTORY" plan -detailed-exitcode \
    -input=false -lock-timeout=10m -out="$LAST_PLAN_FILE" \
    "${secret_var_file_argument[@]}" \
    -var="application_image_digests=${application_digests_json}" \
    -var="database_migrations_image_digest=${migration_digest}" \
    -var="active_applications=${active_applications}" >"$plan_log" 2>&1
  plan_exit=$?
  set -e
  if ((plan_exit == 1)); then
    printf 'Terraform plan failed for phase %s; temporary diagnostics will be deleted.\n' "$phase_name" >&2
    exit 1
  fi
  terraform -chdir="$ACA_TERRAFORM_DIRECTORY" show -json "$LAST_PLAN_FILE" >"$plan_json"
  inspect_plan_json "$plan_json" "$phase_name" "$allowed_create_scope"
}

apply_validated_plan() {
  local phase_name="$1"
  local apply_log
  apply_log="${PLAN_DIRECTORY}/$(basename "$LAST_PLAN_FILE").apply.log"
  [[ -s "$LAST_PLAN_FILE" ]] || {
    printf 'Validated Terraform plan is unavailable for phase %s.\n' "$phase_name" >&2
    exit 1
  }
  printf 'Applying exact validated ACA plan: %s\n' "$phase_name"
  if ! terraform -chdir="$ACA_TERRAFORM_DIRECTORY" apply \
    -input=false -lock-timeout=10m "$LAST_PLAN_FILE" >"$apply_log" 2>&1; then
    printf 'Terraform apply failed for phase %s; temporary diagnostics will be deleted.\n' "$phase_name" >&2
    exit 1
  fi
}

safe_plan_and_apply() {
  create_safe_plan "$@"
  apply_validated_plan "$2"
}

run_database_migrations() {
  local execution_name execution_status started_at elapsed_seconds
  echo "Starting the database migration job."
  execution_name="$(az containerapp job start --name "$ACA_MIGRATIONS_JOB_NAME" \
    --resource-group "$ACA_RESOURCE_GROUP_NAME" --query name \
    --output tsv --only-show-errors)"
  [[ -n "$execution_name" && "$execution_name" != "null" ]] || {
    echo "Azure did not return the migration execution name." >&2
    exit 1
  }
  printf 'Tracking migration execution started by this release: %s\n' "$execution_name"
  started_at="$SECONDS"
  while true; do
    execution_status=""
    if execution_status="$(az containerapp job execution show \
      --name "$ACA_MIGRATIONS_JOB_NAME" --resource-group "$ACA_RESOURCE_GROUP_NAME" \
      --job-execution-name "$execution_name" --query properties.status \
      --output tsv --only-show-errors 2>/dev/null)"; then
      case "$execution_status" in
        Succeeded)
          printf 'Migration execution %s succeeded.\n' "$execution_name"
          return
          ;;
        Failed | Canceled | Cancelled | Stopped)
          printf 'Migration execution %s ended with status %s.\n' "$execution_name" "$execution_status" >&2
          exit 1
          ;;
      esac
    fi
    elapsed_seconds=$((SECONDS - started_at))
    if ((elapsed_seconds >= MIGRATIONS_TIMEOUT_SECONDS)); then
      printf 'Migration execution %s timed out after %s seconds (last status: %s).\n' \
        "$execution_name" "$MIGRATIONS_TIMEOUT_SECONDS" "${execution_status:-unavailable}" >&2
      exit 1
    fi
    printf 'Migration execution %s status: %s\n' "$execution_name" "${execution_status:-not-yet-available}"
    sleep "$MIGRATIONS_POLL_INTERVAL_SECONDS"
  done
}

latest_revision_name() {
  az containerapp show --name "$1" --resource-group "$ACA_RESOURCE_GROUP_NAME" \
    --query properties.latestRevisionName --output tsv --only-show-errors
}

wait_for_healthy_revision() {
  local application="$1" expected_revision="$2"
  local ready_revision health_state provisioning_state started_at elapsed_seconds
  local revision_details_output
  local -a revision_details=()
  [[ -n "$expected_revision" && "$expected_revision" != "null" ]] || {
    printf 'Azure did not return the expected revision for %s.\n' "$application" >&2
    exit 1
  }
  printf 'Waiting for exact healthy revision %s of %s.\n' "$expected_revision" "$application"
  started_at="$SECONDS"
  while true; do
    ready_revision="$(az containerapp show --name "$application" \
      --resource-group "$ACA_RESOURCE_GROUP_NAME" --query properties.latestReadyRevisionName \
      --output tsv --only-show-errors 2>/dev/null || true)"
    health_state=""
    provisioning_state=""
    revision_details_output="$(az containerapp revision show \
      --name "$application" --resource-group "$ACA_RESOURCE_GROUP_NAME" \
      --revision "$expected_revision" --query '[properties.healthState, properties.provisioningState]' \
      --output tsv --only-show-errors 2>/dev/null || true)"
    if parse_exact_required_tsv_lines 2 "$revision_details_output" revision_details; then
      health_state="${revision_details[0]}"
      provisioning_state="${revision_details[1]}"
    fi
    if [[ "$ready_revision" == "$expected_revision" && "$health_state" == "Healthy" && \
      "$provisioning_state" == "Provisioned" ]]; then
      DEPLOYED_REVISIONS["$application"]="$expected_revision"
      printf 'Application %s is healthy on expected revision %s.\n' "$application" "$expected_revision"
      return
    fi
    if [[ "$health_state" == "Unhealthy" || "$provisioning_state" == "Failed" ]]; then
      printf 'Expected revision %s of %s is unhealthy; release stopped without deleting prior revisions.\n' \
        "$expected_revision" "$application" >&2
      exit 1
    fi
    elapsed_seconds=$((SECONDS - started_at))
    if ((elapsed_seconds >= APP_HEALTH_TIMEOUT_SECONDS)); then
      printf 'Expected revision %s of %s did not become healthy within %s seconds.\n' \
        "$expected_revision" "$application" "$APP_HEALTH_TIMEOUT_SECONDS" >&2
      exit 1
    fi
    sleep "$APP_HEALTH_POLL_INTERVAL_SECONDS"
  done
}

deploy_application_phase() {
  local phase_slug="$1" phase_name="$2" active_applications="$3" application="$4"
  local expected_revision
  # The plan helper reads this associative map by its variable name.
  # shellcheck disable=SC2034
  ROLLOUT_APPLICATION_DIGESTS["$application"]="${DESIRED_APPLICATION_DIGESTS[$application]}"
  safe_plan_and_apply "$phase_slug" "$phase_name" ROLLOUT_APPLICATION_DIGESTS \
    "$DESIRED_MIGRATION_DIGEST" "$active_applications" none
  expected_revision="$(latest_revision_name "$application")"
  wait_for_healthy_revision "$application" "$expected_revision"
}

assert_public_http_status() {
  local label="$1" url="$2" expected_status="$3" status
  status="$(curl --silent --show-error --output /dev/null --write-out '%{http_code}' \
    --connect-timeout 5 --max-time 30 --retry 6 --retry-delay 5 --retry-connrefused "$url")" || {
    printf 'Public health check failed for %s at %s.\n' "$label" "$url" >&2
    exit 1
  }
  [[ "$status" == "$expected_status" ]] || {
    printf 'Public health check for %s returned HTTP %s instead of %s at %s.\n' \
      "$label" "$status" "$expected_status" "$url" >&2
    exit 1
  }
  printf 'Public health check: %s URL=%s HTTP=%s\n' "$label" "$url" "$status"
}

verify_eureka_registrations() {
  local gateway_revision="${DEPLOYED_REVISIONS[gateway]:-}"
  local exec_output="${PLAN_DIRECTORY}/eureka-check.log" command
  [[ -n "$gateway_revision" ]] || {
    echo "Gateway revision is unavailable for the Eureka registration check." >&2
    exit 1
  }
  command="sh -c 'for app in GATEWAY USER-SERVICE GAMES-SERVICE LIBRARY-SERVICE ORDER-SERVICE PAYMENT-SERVICE; do wget -qO- http://localhost:8222/actuator/health | grep -Eq \"\\\"\${app}\\\"[[:space:]]*:[[:space:]]*1\" || exit 1; done; echo EUREKA_REGISTRY_OK'"
  if ! az containerapp exec --name gateway --resource-group "$ACA_RESOURCE_GROUP_NAME" \
    --revision "$gateway_revision" --container gateway --command "$command" \
    >"$exec_output" 2>&1; then
    echo "Eureka registration check failed inside the healthy Gateway revision." >&2
    exit 1
  fi
  grep -q 'EUREKA_REGISTRY_OK' "$exec_output" || {
    echo "Eureka did not report exactly one healthy instance for every expected service." >&2
    exit 1
  }
  echo "Eureka registration check: all six expected applications have exactly one instance."
}

run_post_deployment_health_checks() {
  local client_fqdn client_url gateway_route_url
  client_fqdn="$(az containerapp show --name client --resource-group "$ACA_RESOURCE_GROUP_NAME" \
    --query properties.configuration.ingress.fqdn --output tsv --only-show-errors)"
  [[ -n "$client_fqdn" && "$client_fqdn" != "null" ]] || {
    echo "Azure did not return the public client FQDN." >&2
    exit 1
  }
  client_url="https://${client_fqdn}"
  gateway_route_url="${client_url}/api/v1/games"
  assert_public_http_status "client" "$client_url/" 200
  assert_public_http_status "public Gateway games route" "$gateway_route_url" 200
  verify_eureka_registrations
  echo "All Container App revisions, public routes, Eureka registrations, and services are healthy."
}

prepare_stable_redeployment_secrets() {
  REDEPLOY_SECRET_VAR_FILE="${PLAN_DIRECTORY}/stable-redeployment-secrets.tfvars.json"
  # A routine redeploy carries forward the secrets from the last applied
  # Terraform release, which created the running revisions. Reading live ACA
  # app-scope secrets here would be unsafe: Azure can update them without
  # restarting those revisions. The refreshed plan still detects and refuses
  # any difference between this state snapshot and Azure.
  if ! terraform -chdir="$ACA_TERRAFORM_DIRECTORY" show -json \
    | jq -e '
      def module_resources:
        .resources[]?, (.child_modules[]? | module_resources);
      [.values.root_module | module_resources] as $resources
      | def resource_values($address; $label):
          ([$resources[] | select(.address == $address)]) as $matches
          | if ($matches | length) != 1 then
              error("Terraform state has an unexpected resource count for " + $label)
            else
              $matches[0].values
            end;
      def secret_map($address; $expected_names; $label):
        (resource_values($address; $label).secret // null) as $items
        | if ($items | type) != "array" then
            error("Terraform state has malformed secret metadata for " + $label)
          elif ([$items[]?.name] | sort) != ($expected_names | sort) then
            error("Terraform state has an unexpected secret topology for " + $label)
          elif any($items[]; (.value | type) != "string" or (.value | length) == 0) then
            error("Terraform state has an unavailable secret value for " + $label)
          else
            reduce $items[] as $item ({}; .[$item.name] = $item.value)
          end;
      secret_map("module.apps.azurerm_container_app.this[\"config-server\"]"; ["jwt-secret"]; "config-server") as $config_values
      | secret_map("module.apps.azurerm_container_app.this[\"gateway\"]"; ["jwt-secret"]; "gateway") as $gateway_values
      | secret_map("module.apps.azurerm_container_app.this[\"games-service\"]"; ["db-password"]; "games-service") as $games_values
      | secret_map("module.apps.azurerm_container_app.this[\"library-service\"]"; ["mongo-uri"]; "library-service") as $library_values
      | secret_map("module.apps.azurerm_container_app.this[\"order-service\"]"; ["db-password"]; "order-service") as $order_values
      | secret_map("module.apps.azurerm_container_app.this[\"payment-service\"]"; ["db-password"]; "payment-service") as $payment_values
      | secret_map("module.apps.azurerm_container_app.this[\"user-service\"]"; ["admin-password", "jwt-secret", "mongo-uri"]; "user-service") as $user_values
      | secret_map("module.apps.azurerm_container_app_job.database_migrations"; ["postgres-admin-password", "postgres-app-password"]; "database migration job") as $migration_values
      | if $config_values["jwt-secret"] != $gateway_values["jwt-secret"]
          or $config_values["jwt-secret"] != $user_values["jwt-secret"] then
          error("Deployed ACA JWT secrets are inconsistent")
        elif $games_values["db-password"] != $order_values["db-password"]
          or $games_values["db-password"] != $payment_values["db-password"]
          or $games_values["db-password"] != $migration_values["postgres-app-password"] then
          error("Deployed ACA PostgreSQL application passwords are inconsistent")
        elif $library_values["mongo-uri"] != $user_values["mongo-uri"] then
          error("Deployed ACA Cosmos MongoDB URIs are inconsistent")
        else
          {
            application_jwt_secret: $config_values["jwt-secret"],
            postgresql_application_password: $games_values["db-password"],
            application_admin_password: $user_values["admin-password"],
            postgresql_administrator_password: $migration_values["postgres-admin-password"]
          }
        end
    ' >"$REDEPLOY_SECRET_VAR_FILE"; then
    echo "Unable to establish consistent secrets from the last applied Terraform release." >&2
    return 1
  fi
  chmod 600 "$REDEPLOY_SECRET_VAR_FILE"

  jq -r '[
    "CircleCI application JWT candidate matches the deployed ACA value: \(.application_jwt_secret == env.TF_VAR_application_jwt_secret)",
    "CircleCI PostgreSQL application password candidate matches the deployed ACA value: \(.postgresql_application_password == env.TF_VAR_postgresql_application_password)",
    "CircleCI application admin password candidate matches the deployed ACA value: \(.application_admin_password == env.TF_VAR_application_admin_password)",
    "CircleCI PostgreSQL administrator password candidate matches the deployed migration-job value: \(.postgresql_administrator_password == env.TF_VAR_postgresql_administrator_password)"
  ] | .[]' "$REDEPLOY_SECRET_VAR_FILE"

  echo "Last applied Terraform secret topology and cross-resource values verified for stable redeployment."
}

prepare_rollout_state() {
  if [[ "$DETECTED_RELEASE_MODE" == "redeploy" ]]; then
    load_current_healthy_release
    prepare_stable_redeployment_secrets
    copy_digest_map CURRENT_APPLICATION_DIGESTS ROLLOUT_APPLICATION_DIGESTS
  else
    copy_digest_map DESIRED_APPLICATION_DIGESTS ROLLOUT_APPLICATION_DIGESTS
    CURRENT_MIGRATION_DIGEST="$DESIRED_MIGRATION_DIGEST"
  fi
}

run_plan_only() {
  if [[ "$DETECTED_RELEASE_MODE" == "initial" ]]; then
    create_safe_plan initial-release-preview "initial bootstrap preview" \
      ROLLOUT_APPLICATION_DIGESTS "$DESIRED_MIGRATION_DIGEST" \
      "$NO_ACTIVE_APPLICATIONS" initial-apps-job
  else
    create_safe_plan migration-preview "redeployment migration preview" \
      ROLLOUT_APPLICATION_DIGESTS "$DESIRED_MIGRATION_DIGEST" \
      "$ALL_ACTIVE_APPLICATIONS" pre-migration
  fi
  printf 'ACA plan gate passed: mode=%s add=%s change=%s destroy=%s; no apply executed.\n' \
    "$DETECTED_RELEASE_MODE" "$LAST_PLAN_ADD_COUNT" "$LAST_PLAN_CHANGE_COUNT" \
    "$LAST_PLAN_DESTROY_COUNT"
}

run_deployment() {
  local bootstrap_create_scope="pre-migration" bootstrap_active_applications="$ALL_ACTIVE_APPLICATIONS"
  if [[ "$DETECTED_RELEASE_MODE" == "initial" ]]; then
    bootstrap_create_scope="initial-apps-job"
    bootstrap_active_applications="$NO_ACTIVE_APPLICATIONS"
  fi
  safe_plan_and_apply infrastructure-bootstrap "infrastructure/bootstrap" \
    ROLLOUT_APPLICATION_DIGESTS "$CURRENT_MIGRATION_DIGEST" \
    "$bootstrap_active_applications" "$bootstrap_create_scope"
  safe_plan_and_apply migration-job "migration job update" \
    ROLLOUT_APPLICATION_DIGESTS "$DESIRED_MIGRATION_DIGEST" \
    "$bootstrap_active_applications" pre-migration
  run_database_migrations
  deploy_application_phase config-server "Config Server revision" "$CONFIG_ACTIVE_APPLICATIONS" config-server
  deploy_application_phase discovery-service "Discovery revision" "$DISCOVERY_ACTIVE_APPLICATIONS" discovery-service
  deploy_application_phase gateway "Gateway revision" "$GATEWAY_ACTIVE_APPLICATIONS" gateway
  deploy_application_phase games-service "Games service revision" "$GAMES_ACTIVE_APPLICATIONS" games-service
  deploy_application_phase library-service "Library service revision" "$LIBRARY_ACTIVE_APPLICATIONS" library-service
  deploy_application_phase order-service "Order service revision" "$ORDER_ACTIVE_APPLICATIONS" order-service
  deploy_application_phase payment-service "Payment service revision" "$PAYMENT_ACTIVE_APPLICATIONS" payment-service
  deploy_application_phase user-service "User service revision" "$BUSINESS_ACTIVE_APPLICATIONS" user-service
  deploy_application_phase client "Client revision and complete application set" "$ALL_ACTIVE_APPLICATIONS" client
  run_post_deployment_health_checks
  echo "ACA release completed successfully without deleting prior applications or revisions."
}

cleanup_plan_directory() {
  if [[ -n "$PLAN_DIRECTORY" && "$PLAN_DIRECTORY" == /tmp/aca-terraform-plans.* ]]; then
    rm -rf -- "$PLAN_DIRECTORY"
  fi
}

main() {
  local operation="${1:-}"
  [[ "$operation" == "plan" || "$operation" == "deploy" ]] || {
    echo "Usage: deploy-aca.sh plan|deploy" >&2
    exit 2
  }
  validate_release_inputs
  export TF_IN_AUTOMATION=true
  export TF_VAR_subscription_id="$AZURE_SUBSCRIPTION_ID"
  export TF_VAR_resource_group_name="$ACA_RESOURCE_GROUP_NAME"
  export TF_VAR_acr_name="$ACA_ACR_NAME"
  export TF_VAR_project_name="$ACA_PROJECT_NAME"
  export TF_VAR_environment="$ACA_ENVIRONMENT_NAME"
  export TF_VAR_postgresql_application_username="${TF_VAR_postgresql_application_username:-steam_app}"
  umask 077
  PLAN_DIRECTORY="$(mktemp -d /tmp/aca-terraform-plans.XXXXXX)"
  trap cleanup_plan_directory EXIT
  aca_authenticate_with_circleci_oidc
  echo "Azure OIDC authentication and repository/branch binding succeeded."
  verify_release_images
  initialize_terraform
  load_release_inventories
  detect_release_mode
  prepare_rollout_state
  if [[ "$operation" == "plan" ]]; then
    run_plan_only
  else
    run_deployment
  fi
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
