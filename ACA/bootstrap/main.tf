data "azurerm_resource_group" "current" {
  name = var.resource_group_name
}

data "azurerm_client_config" "current" {}

resource "azurerm_storage_account" "terraform_state" {
  name                = var.state_storage_account_name
  resource_group_name = data.azurerm_resource_group.current.name
  location            = data.azurerm_resource_group.current.location

  account_kind             = "StorageV2"
  account_tier             = "Standard"
  account_replication_type = "LRS"

  https_traffic_only_enabled      = true
  min_tls_version                 = "TLS1_2"
  allow_nested_items_to_be_public = false
  public_network_access_enabled   = true

  shared_access_key_enabled = true

  # Préférence OAuth dans le portail Azure.
  # Cela ne désactive pas les clés nécessaires au provider AzureRM.
  default_to_oauth_authentication = true

  # Aucun compte local Storage/SFTP n'est nécessaire pour Terraform state.
  local_user_enabled = false

  blob_properties {
    versioning_enabled = true

    delete_retention_policy {
      days = 30
    }

    container_delete_retention_policy {
      days = 30
    }
  }

  tags = merge(
    {
      Project     = "Ghassen Dridi"
      Environment = "aca"
      ManagedBy   = "Terraform"
      Workload    = "Ghassen Dridi"
    },
    var.tags
  )

  lifecycle {
    prevent_destroy = true
  }
}

resource "azurerm_storage_container" "terraform_state" {
  name                  = var.state_container_name
  storage_account_id    = azurerm_storage_account.terraform_state.id
  container_access_type = "private"

  lifecycle {
    prevent_destroy = true
  }
}

resource "azurerm_role_assignment" "terraform_state_operator" {
  scope                = azurerm_storage_account.terraform_state.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = data.azurerm_client_config.current.object_id
}