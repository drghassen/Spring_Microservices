#!/usr/bin/env bash

set -euo pipefail

readonly ACA_TERRAFORM_DIRECTORY="ACA"
readonly ACA_RESOURCE_GROUP_NAME="${ACA_RESOURCE_GROUP_NAME:-internship_proxym}"
readonly ACA_ACR_NAME="${ACA_ACR_NAME:-ghassenspringservices}"
readonly ACA_PROJECT_NAME="${ACA_PROJECT_NAME:-ghassen-dridi}"
readonly ACA_ENVIRONMENT_NAME="${ACA_ENVIRONMENT_NAME:-aca}"
readonly ACA_MIGRATIONS_JOB_NAME="ghassen-dridi-aca-db-migrate"
readonly ACA_TF_STATE_RESOURCE_GROUP_NAME="${ACA_TF_STATE_RESOURCE_GROUP_NAME:-internship_proxym}"
readonly ACA_TF_STATE_STORAGE_ACCOUNT_NAME="${ACA_TF_STATE_STORAGE_ACCOUNT_NAME:-stghassendridiaca5304}"
readonly ACA_TF_STATE_CONTAINER_NAME="${ACA_TF_STATE_CONTAINER_NAME:-tfstate}"
readonly ACA_TF_STATE_KEY="${ACA_TF_STATE_KEY:-aca/terraform.tfstate}"
readonly ACA_EXPECTED_CIRCLECI_PROJECT_USERNAME="drghassen"
readonly ACA_EXPECTED_CIRCLECI_PROJECT_REPONAME="Spring_Microservices"
readonly ACA_EXPECTED_CIRCLECI_VCS_ORIGIN="github.com/${ACA_EXPECTED_CIRCLECI_PROJECT_USERNAME}/${ACA_EXPECTED_CIRCLECI_PROJECT_REPONAME}"
readonly ACA_EXPECTED_CIRCLECI_VCS_REF="refs/heads/master"

readonly ACA_APPLICATIONS=(
  client
  config-server
  discovery-service
  gateway
  games-service
  library-service
  order-service
  payment-service
  user-service
)

aca_require_environment_variable() {
  local variable_name="$1"

  [[ -n "${!variable_name:-}" ]] || {
    printf '%s must be defined in the aca-deploy CircleCI context.\n' "$variable_name" >&2
    exit 1
  }
}

aca_require_command() {
  local command_name="$1"

  command -v "$command_name" >/dev/null 2>&1 || {
    printf '%s is required for the ACA operation.\n' "$command_name" >&2
    exit 1
  }
}

aca_authenticate_with_circleci_oidc() {
  local oidc_token
  local selected_subscription_id
  local selected_tenant_id

  [[ "${CIRCLE_BRANCH:-}" == "master" ]] || {
    echo "Sensitive ACA operations are restricted to the master branch." >&2
    exit 1
  }
  [[ "${CIRCLE_PROJECT_USERNAME:-}" == "$ACA_EXPECTED_CIRCLECI_PROJECT_USERNAME" && \
    "${CIRCLE_PROJECT_REPONAME:-}" == "$ACA_EXPECTED_CIRCLECI_PROJECT_REPONAME" ]] || {
    echo "Sensitive ACA operations are restricted to the expected GitHub repository." >&2
    exit 1
  }

  oidc_token="$(
    circleci run oidc get \
      --claims '{"aud":"api://AzureADTokenExchange"}'
  )"
  [[ -n "$oidc_token" ]] || {
    echo "CircleCI did not return an OIDC token." >&2
    exit 1
  }

  OIDC_TOKEN="$oidc_token" \
    ACA_EXPECTED_CIRCLECI_VCS_ORIGIN="$ACA_EXPECTED_CIRCLECI_VCS_ORIGIN" \
    ACA_EXPECTED_CIRCLECI_VCS_REF="$ACA_EXPECTED_CIRCLECI_VCS_REF" \
    python3 - <<'PY'
import base64
import json
import os

token = os.environ["OIDC_TOKEN"]
try:
    payload = token.split(".", 2)[1]
    payload += "=" * (-len(payload) % 4)
    claims = json.loads(base64.urlsafe_b64decode(payload))
except (IndexError, ValueError, json.JSONDecodeError) as error:
    raise SystemExit("Unable to validate the CircleCI OIDC token claims") from error

audience = claims.get("aud", [])
if isinstance(audience, str):
    audience = [audience]

if "api://AzureADTokenExchange" not in audience:
    raise SystemExit("CircleCI OIDC token has an unexpected audience")
if claims.get("oidc.circleci.com/vcs-origin") != os.environ["ACA_EXPECTED_CIRCLECI_VCS_ORIGIN"]:
    raise SystemExit("CircleCI OIDC token has an unexpected repository binding")
if claims.get("oidc.circleci.com/vcs-ref") != os.environ["ACA_EXPECTED_CIRCLECI_VCS_REF"]:
    raise SystemExit("CircleCI OIDC token has an unexpected branch binding")
PY

  az login \
    --service-principal \
    --username "$AZURE_CLIENT_ID" \
    --tenant "$AZURE_TENANT_ID" \
    --federated-token "$oidc_token" \
    --output none
  unset oidc_token

  az account set --subscription "$AZURE_SUBSCRIPTION_ID"
  read -r selected_subscription_id selected_tenant_id < <(
    az account show --query '[id, tenantId]' --output tsv
  )
  [[ "$selected_subscription_id" == "$AZURE_SUBSCRIPTION_ID" && \
    "$selected_tenant_id" == "$AZURE_TENANT_ID" ]] || {
    echo "Azure selected an unexpected subscription or tenant." >&2
    exit 1
  }
}
