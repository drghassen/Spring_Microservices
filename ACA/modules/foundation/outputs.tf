output "log_analytics_workspace_id" {
  description = "ID of the Log Analytics Workspace used by the Container Apps environment."
  value       = azurerm_log_analytics_workspace.this.id
}

output "log_analytics_workspace_name" {
  description = "Name of the Log Analytics Workspace used by the Container Apps environment."
  value       = azurerm_log_analytics_workspace.this.name
}

output "container_app_environment_id" {
  description = "ID of the Azure Container Apps environment."
  value       = azurerm_container_app_environment.this.id
}

output "container_app_environment_name" {
  description = "Name of the Azure Container Apps environment."
  value       = azurerm_container_app_environment.this.name
}

output "container_app_environment_default_domain" {
  description = "Default domain assigned to the Azure Container Apps environment."
  value       = azurerm_container_app_environment.this.default_domain
}
