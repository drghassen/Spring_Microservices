output "apps_managed_identity_id" {
  description = "Resource ID of the managed identity for future Azure Container Apps."
  value       = azurerm_user_assigned_identity.apps.id
}

output "apps_managed_identity_client_id" {
  description = "Client ID of the managed identity for future Azure Container Apps."
  value       = azurerm_user_assigned_identity.apps.client_id
}

output "apps_managed_identity_principal_id" {
  description = "Principal ID of the managed identity for future Azure Container Apps."
  value       = azurerm_user_assigned_identity.apps.principal_id
}

output "apps_managed_identity_name" {
  description = "Name of the managed identity for future Azure Container Apps."
  value       = azurerm_user_assigned_identity.apps.name
}
