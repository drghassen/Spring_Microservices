output "resource_group_name" {
  description = "Name of the existing Resource Group used by the foundation."
  value       = data.azurerm_resource_group.current.name
}

output "resource_group_id" {
  description = "ID of the existing Resource Group used by the foundation."
  value       = data.azurerm_resource_group.current.id
}

output "acr_id" {
  description = "ID of the existing Azure Container Registry used as the image source."
  value       = data.azurerm_container_registry.current.id
}

output "acr_login_server" {
  description = "Login server of the existing Azure Container Registry."
  value       = data.azurerm_container_registry.current.login_server
}

output "location" {
  description = "Effective Azure location read from the existing Resource Group."
  value       = data.azurerm_resource_group.current.location
}

output "subscription_id" {
  description = "Azure subscription ID selected for this Terraform configuration."
  value       = var.subscription_id
}

output "name_prefix" {
  description = "Standard name prefix for ACA resources."
  value       = local.name_prefix
}

output "effective_tags" {
  description = "Default foundation tags merged with caller-provided tags."
  value       = local.effective_tags
}

output "vnet_id" {
  description = "ID of the virtual network created for Azure Container Apps."
  value       = module.network.vnet_id
}

output "vnet_name" {
  description = "Name of the virtual network created for Azure Container Apps."
  value       = module.network.vnet_name
}

output "aca_infrastructure_subnet_id" {
  description = "ID of the subnet delegated to Azure Container Apps environments."
  value       = module.network.aca_infrastructure_subnet_id
}

output "private_endpoints_subnet_id" {
  description = "ID of the subnet reserved for future private endpoints."
  value       = module.network.private_endpoints_subnet_id
}

output "log_analytics_workspace_id" {
  description = "ID of the Log Analytics Workspace used by the Container Apps environment."
  value       = module.foundation.log_analytics_workspace_id
}

output "log_analytics_workspace_name" {
  description = "Name of the Log Analytics Workspace used by the Container Apps environment."
  value       = module.foundation.log_analytics_workspace_name
}

output "container_app_environment_id" {
  description = "ID of the Azure Container Apps environment."
  value       = module.foundation.container_app_environment_id
}

output "container_app_environment_name" {
  description = "Name of the Azure Container Apps environment."
  value       = module.foundation.container_app_environment_name
}

output "container_app_environment_default_domain" {
  description = "Default domain assigned to the Azure Container Apps environment."
  value       = module.foundation.container_app_environment_default_domain
}

output "postgresql_server_id" {
  description = "Resource ID of the PostgreSQL Flexible Server."
  value       = module.data.postgresql_server_id
}

output "postgresql_server_fqdn" {
  description = "Private DNS hostname used by future ACA workloads to reach PostgreSQL."
  value       = module.data.postgresql_server_fqdn
}

output "postgresql_database_name" {
  description = "Shared PostgreSQL database required by Games, Order, and Payment."
  value       = module.data.postgresql_database_name
}

output "cosmos_mongodb_account_id" {
  description = "Resource ID of the Azure Cosmos DB API for MongoDB account."
  value       = module.data.cosmos_mongodb_account_id
}

output "apps_managed_identity_id" {
  description = "Resource ID of the managed identity for future Azure Container Apps."
  value       = module.identities.apps_managed_identity_id
}

output "apps_managed_identity_client_id" {
  description = "Client ID of the managed identity for future Azure Container Apps."
  value       = module.identities.apps_managed_identity_client_id
}

output "apps_managed_identity_principal_id" {
  description = "Principal ID of the managed identity for future Azure Container Apps."
  value       = module.identities.apps_managed_identity_principal_id
}

output "apps_managed_identity_name" {
  description = "Name of the managed identity for future Azure Container Apps."
  value       = module.identities.apps_managed_identity_name
}

output "container_app_ids" {
  description = "Non-sensitive map of Azure Container App resource IDs by application name."
  value       = module.apps.container_app_ids
}

output "container_app_fqdns" {
  description = "Non-sensitive map of Container App ingress FQDNs by application name."
  value       = module.apps.container_app_fqdns
}

output "client_fqdn" {
  description = "Ingress FQDN of the externally available client application."
  value       = module.apps.client_fqdn
}

output "client_url" {
  description = "HTTPS URL of the externally available client application."
  value       = module.apps.client_url
}

output "gateway_fqdn" {
  description = "Internal ingress FQDN of the gateway Container App."
  value       = module.apps.gateway_fqdn
}
