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
