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
