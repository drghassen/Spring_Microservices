#!/usr/bin/env bash

set -euo pipefail

# shellcheck source-path=SCRIPTDIR
# shellcheck source=lib/aca-deployment.sh
source "$(dirname "$0")/lib/aca-deployment.sh"

for required_variable in AZURE_CLIENT_ID AZURE_TENANT_ID AZURE_SUBSCRIPTION_ID; do
  aca_require_environment_variable "$required_variable"
done
for required_command in az circleci; do
  aca_require_command "$required_command"
done

aca_authenticate_with_circleci_oidc
echo "OIDC_AUTH=PASS"
echo "AZURE_SUBSCRIPTION=PASS"
echo "AZURE_TENANT=PASS"

az group show \
  --name "$ACA_RESOURCE_GROUP_NAME" \
  --query id \
  --output tsv \
  --only-show-errors \
  >/dev/null
echo "RESOURCE_GROUP_READ=PASS"

az storage blob show \
  --account-name "$ACA_TF_STATE_STORAGE_ACCOUNT_NAME" \
  --container-name "$ACA_TF_STATE_CONTAINER_NAME" \
  --name "$ACA_TF_STATE_KEY" \
  --auth-mode login \
  --query name \
  --output tsv \
  --only-show-errors \
  >/dev/null
echo "TFSTATE_READ=PASS"
echo "TFSTATE_WRITE=NOT_TESTED (a successful blob read does not prove write permission)"
