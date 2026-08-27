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
  postgresql_subnet_address_prefix         = var.postgresql_subnet_address_prefix
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

module "data" {
  source = "./modules/data"

  resource_group_name               = data.azurerm_resource_group.current.name
  location                          = data.azurerm_resource_group.current.location
  name_prefix                       = local.name_prefix
  tags                              = local.effective_tags
  virtual_network_id                = module.network.vnet_id
  postgresql_delegated_subnet_id    = module.network.postgresql_subnet_id
  postgresql_administrator_login    = var.postgresql_administrator_login
  postgresql_administrator_password = var.postgresql_administrator_password
}

module "identities" {
  source = "./modules/identities"

  resource_group_name = data.azurerm_resource_group.current.name
  location            = data.azurerm_resource_group.current.location
  name_prefix         = local.name_prefix
  acr_id              = data.azurerm_container_registry.current.id
  tags                = local.effective_tags
}

module "apps" {
  source = "./modules/apps"

  resource_group_name                      = data.azurerm_resource_group.current.name
  location                                 = data.azurerm_resource_group.current.location
  container_app_environment_id             = module.foundation.container_app_environment_id
  container_app_environment_default_domain = module.foundation.container_app_environment_default_domain
  apps_managed_identity_id                 = module.identities.apps_managed_identity_id
  acr_login_server                         = data.azurerm_container_registry.current.login_server
  application_image_digests                = var.application_image_digests
  database_migrations_image_digest         = var.database_migrations_image_digest
  active_applications                      = var.active_applications
  postgresql_server_fqdn                   = module.data.postgresql_server_fqdn
  postgresql_database_name                 = module.data.postgresql_database_name
  postgresql_administrator_login           = var.postgresql_administrator_login
  postgresql_administrator_password        = var.postgresql_administrator_password
  postgresql_application_username          = var.postgresql_application_username
  postgresql_application_password          = var.postgresql_application_password
  cosmos_mongodb_uri                       = module.data.cosmos_mongodb_uri
  application_jwt_secret                   = var.application_jwt_secret
  application_admin_password               = var.application_admin_password
  tags                                     = local.effective_tags
}

# No image is selected at the foundation stage. Future Container Apps must
# use immutable CircleCI-produced image tags; legacy build-31 images are not
# valid deployment inputs.
