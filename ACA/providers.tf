provider "azurerm" {
  features {}

  # Local foundation validation uses the identity already authenticated by
  # Azure CLI. The subscription is supplied explicitly through TF_VAR_...
  subscription_id = var.subscription_id
  use_cli         = true
}
