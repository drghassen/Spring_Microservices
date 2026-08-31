#!/usr/bin/env bash

set -euo pipefail

command_name="${0##*/}"

case "$command_name" in
  az)
    if [[ "${1:-}" == "account" && "${2:-}" == "show" ]]; then
      if [[ " $* " == *" --query name "* ]]; then
        echo "Mock Azure Subscription"
      elif [[ " $* " == *" --query id "* ]]; then
        echo "00000000-0000-0000-0000-000000000001"
      else
        echo "Unexpected az account query." >&2
        exit 2
      fi
    elif [[ "${1:-}" == "resource" && "${2:-}" == "list" ]]; then
      [[ " $* " == *" --resource-group internship_proxym "* ]] || {
        echo "Azure inventory did not target internship_proxym." >&2
        exit 2
      }
      if [[ "${MOCK_AZ_MODE:-success}" == "inventory_fail" ]]; then
        echo "Mock Azure inventory failure." >&2
        exit 1
      fi
      printf '%s\n' '[{"id":"/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/internship_proxym/providers/Microsoft.Network/virtualNetworks/main"}]'
    else
      echo "Unexpected Azure CLI invocation." >&2
      exit 2
    fi
    ;;
  prowler)
    if [[ "${1:-}" == "--version" ]]; then
      echo "Prowler 5.40.0"
      exit 0
    fi
    [[ "${1:-}" == "azure" ]] || {
      echo "Mock Prowler did not receive the Azure provider." >&2
      exit 2
    }
    az_cli_auth_seen=false
    subscription_seen=false
    html_seen=false
    csv_seen=false
    json_ocsf_seen=false
    for argument in "$@"; do
      case "$argument" in
        --az-cli-auth) az_cli_auth_seen=true ;;
        00000000-0000-0000-0000-000000000001) subscription_seen=true ;;
        html) html_seen=true ;;
        csv) csv_seen=true ;;
        json-ocsf) json_ocsf_seen=true ;;
        --azure-resource-group|--resource-group)
          echo "Prowler received a forbidden resource-group scan flag." >&2
          exit 2
          ;;
      esac
    done
    if [[ "$az_cli_auth_seen" != true || "$subscription_seen" != true || \
          "$html_seen" != true || "$csv_seen" != true || "$json_ocsf_seen" != true ]]; then
      echo "Prowler subscription scan arguments were incomplete." >&2
      exit 2
    fi
    printf 'called\n' >"${MOCK_PROWLER_MARKER:?}"
    if [[ "${MOCK_PROWLER_MODE:-success}" == "scan_fail" ]]; then
      echo "Mock Prowler failure." >&2
      exit 7
    fi

    output_directory=""
    while (($#)); do
      if [[ "$1" == "--output-directory" ]]; then
        output_directory="${2:-}"
        break
      fi
      shift
    done
    [[ -n "$output_directory" ]] || {
      echo "Mock Prowler received no output directory." >&2
      exit 2
    }
    mkdir -p "$output_directory"
    printf '<html></html>\n' >"${output_directory}/prowler-output.html"
    printf '{}\n' >"${output_directory}/prowler-output.ocsf.json"

    case "${MOCK_PROWLER_MODE:-success}" in
      missing_csv)
        ;;
      malformed)
        printf '%s\n' 'CHECK_ID;PROVIDER;STATUS;SEVERITY' \
          'bad;azure;FAIL;high' >"${output_directory}/prowler-output.csv"
        ;;
      empty_filter)
        printf '%s\n' \
          'CHECK_ID;PROVIDER;STATUS;SEVERITY;RESOURCE_UID' \
          'other_rg;azure;FAIL;high;/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/elsewhere/providers/Microsoft.Network/virtualNetworks/main' \
          >"${output_directory}/prowler-output.csv"
        ;;
      success)
        printf '%s\n' \
          'CHECK_ID;PROVIDER;STATUS;SEVERITY;RESOURCE_UID' \
          'target;azure;FAIL;high;/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/INTERNSHIP_PROXYM/providers/Microsoft.Network/virtualNetworks/main/subnets/default' \
          'other_rg;azure;FAIL;medium;/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/elsewhere/providers/Microsoft.Network/virtualNetworks/main' \
          'subscription;azure;FAIL;low;/subscriptions/00000000-0000-0000-0000-000000000001' \
          'entra;azure;FAIL;critical;11111111-1111-1111-1111-111111111111' \
          >"${output_directory}/prowler-output.csv"
        ;;
      *)
        echo "Unknown mock Prowler mode." >&2
        exit 2
        ;;
    esac
    ;;
  python)
    real_python="${REAL_PYTHON_BIN:?}"
    if [[ "${MOCK_PYTHON_MODE:-success}" == "metadata_fail" && \
          "${1:-}" == *'/filter-azure-rg-findings.py' ]]; then
      original_arguments=("$@")
      metadata_path=""
      for ((index = 0; index < ${#original_arguments[@]}; index++)); do
        if [[ "${original_arguments[index]}" == "--metadata-json" ]]; then
          metadata_path="${original_arguments[index + 1]:-}"
          break
        fi
      done
      "$real_python" "${original_arguments[@]}"
      [[ -n "$metadata_path" && -e "$metadata_path" ]] && unlink "$metadata_path"
      echo "Mock metadata generation failure." >&2
      exit 1
    fi
    exec "$real_python" "$@"
    ;;
  curl)
    authorization_seen=false
    while IFS= read -r config_line; do
      if [[ "$config_line" == "header = \"Authorization: Token ${DD_TOKEN:?}\"" ]]; then
        authorization_seen=true
      fi
    done
    [[ "$authorization_seen" == true ]] || {
      echo "Authorization was not supplied through curl config." >&2
      exit 2
    }

    scan_type_seen=false
    test_seen=false
    minimum_severity_seen=false
    active_seen=false
    verified_seen=false
    close_old_seen=false
    file_seen=false
    endpoint_seen=false
    for argument in "$@"; do
      case "$argument" in
        'scan_type=Prowler Scan') scan_type_seen=true ;;
        "test=${DD_TEST_ID:?}") test_seen=true ;;
        'minimum_severity=Info') minimum_severity_seen=true ;;
        'active=true') active_seen=true ;;
        'verified=true') verified_seen=true ;;
        'close_old_findings=false') close_old_seen=true ;;
        file=@*';type=text/csv') file_seen=true ;;
        'https://dojo.invalid/api/v2/reimport-scan/') endpoint_seen=true ;;
        --insecure|-k) echo "TLS verification was disabled." >&2; exit 2 ;;
      esac
    done
    if [[ "$scan_type_seen" != true || "$test_seen" != true || \
          "$minimum_severity_seen" != true || "$active_seen" != true || \
          "$verified_seen" != true || "$close_old_seen" != true || \
          "$file_seen" != true || "$endpoint_seen" != true ]]; then
      echo "DefectDojo reimport arguments were incomplete." >&2
      exit 2
    fi
    printf 'called\n' >"${MOCK_CURL_MARKER:?}"
    printf '200'
    ;;
  *)
    echo "Unsupported mock command: $command_name" >&2
    exit 2
    ;;
esac
