# The Resource Group is owned outside this stack and is intentionally read-only.
# This root module reads the Resource Group location and delegates network
# resource creation to the network module below.
data "azurerm_resource_group" "current" {
  name = var.resource_group_name
}

# The registry is owned outside this stack and is intentionally read-only.
data "azurerm_container_registry" "current" {
  name                = var.acr_name
  resource_group_name = var.resource_group_name
}

module "network" {
  source = "./modules/network"

  resource_group_name = data.azurerm_resource_group.current.name
  location            = data.azurerm_resource_group.current.location
  name_prefix         = local.name_prefix
  tags                = local.effective_tags

  vnet_address_space                       = var.vnet_address_space
  aca_infrastructure_subnet_address_prefix = var.aca_infrastructure_subnet_address_prefix
  private_endpoints_subnet_address_prefix  = var.private_endpoints_subnet_address_prefix
}

module "foundation" {
  source = "./modules/foundation"

  resource_group_name             = data.azurerm_resource_group.current.name
  location                        = data.azurerm_resource_group.current.location
  name_prefix                     = local.name_prefix
  tags                            = local.effective_tags
  aca_infrastructure_subnet_id    = module.network.aca_infrastructure_subnet_id
  log_analytics_retention_in_days = var.log_analytics_retention_in_days
}

# No image is selected at the foundation stage. Future Container Apps must
# use immutable CircleCI-produced image tags; legacy build-31 images are not
# valid deployment inputs.
