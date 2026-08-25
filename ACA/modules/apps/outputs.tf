output "container_app_ids" {
  description = "Non-sensitive map of Azure Container App resource IDs by application name."
  value       = { for name, app in azurerm_container_app.this : name => app.id }
}

output "container_app_fqdns" {
  description = "Non-sensitive map of Container App ingress FQDNs by application name."
  value       = { for name, app in azurerm_container_app.this : name => app.ingress[0].fqdn }
}

output "client_fqdn" {
  description = "Ingress FQDN of the externally available client application."
  value       = azurerm_container_app.this["client"].ingress[0].fqdn
}

output "client_url" {
  description = "HTTPS URL of the externally available client application."
  value       = "https://${azurerm_container_app.this["client"].ingress[0].fqdn}"
}

output "gateway_fqdn" {
  description = "Internal ingress FQDN of the gateway Container App."
  value       = azurerm_container_app.this["gateway"].ingress[0].fqdn
}
