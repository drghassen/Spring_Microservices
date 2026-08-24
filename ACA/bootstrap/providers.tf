provider "azurerm" {
  features {}

  subscription_id = var.subscription_id
  use_cli         = true
}