#!/usr/bin/env bash

set -euo pipefail

# shellcheck source-path=SCRIPTDIR
# shellcheck source=lib/aca-deployment.sh
source "$(dirname "$0")/lib/aca-deployment.sh"

require_preflight_inputs() {
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

  for required_command in az circleci jq python3 terraform; do
    aca_require_command "$required_command"
  done

  [[ "$IMAGE_TAG" =~ ^build-[0-9]+$ && "$IMAGE_TAG" != "build-31" ]] || {
    echo "IMAGE_TAG must be an immutable build-<number> tag other than build-31." >&2
    exit 1
  }
}

initialize_backend_read_only() {
  terraform -chdir="$ACA_TERRAFORM_DIRECTORY" init -input=false \
    -backend-config="resource_group_name=${ACA_TF_STATE_RESOURCE_GROUP_NAME}" \
    -backend-config="storage_account_name=${ACA_TF_STATE_STORAGE_ACCOUNT_NAME}" \
    -backend-config="container_name=${ACA_TF_STATE_CONTAINER_NAME}" \
    -backend-config="key=${ACA_TF_STATE_KEY}" \
    -backend-config="use_azuread_auth=true" \
    -backend-config="use_cli=true" >/dev/null

  terraform -chdir="$ACA_TERRAFORM_DIRECTORY" state list >/dev/null
}

require_preflight_inputs
aca_authenticate_with_circleci_oidc

echo "PREFLIGHT_OIDC=PASS"
echo "PREFLIGHT_AZURE_TENANT=PASS"
echo "PREFLIGHT_AZURE_SUBSCRIPTION=PASS"

az group show \
  --name "$ACA_RESOURCE_GROUP_NAME" \
  --query id \
  --output none \
  --only-show-errors
echo "PREFLIGHT_RESOURCE_GROUP=PASS"

az acr show \
  --name "$ACA_ACR_NAME" \
  --resource-group "$ACA_RESOURCE_GROUP_NAME" \
  --query id \
  --output none \
  --only-show-errors
az acr repository list \
  --name "$ACA_ACR_NAME" \
  --output none \
  --only-show-errors
echo "PREFLIGHT_ACR=PASS"

az storage blob show \
  --account-name "$ACA_TF_STATE_STORAGE_ACCOUNT_NAME" \
  --container-name "$ACA_TF_STATE_CONTAINER_NAME" \
  --name "$ACA_TF_STATE_KEY" \
  --auth-mode login \
  --query name \
  --output none \
  --only-show-errors
initialize_backend_read_only
echo "PREFLIGHT_TERRAFORM_BACKEND=PASS"
echo "ACA_PREFLIGHT=PASS"
