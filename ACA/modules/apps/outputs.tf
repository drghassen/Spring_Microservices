output "container_app_ids" {
  description = "Non-sensitive map of Azure Container App resource IDs by application name."
  value       = { for name, app in azurerm_container_app.this : name => app.id }
}

output "container_app_fqdns" {
  description = "Non-sensitive map of Container App ingress FQDNs by application name."
  value       = { for name, app in azurerm_container_app.this : name => try(app.ingress[0].fqdn, null) }
}

output "client_fqdn" {
  description = "Ingress FQDN of the externally available client application."
  value       = try(azurerm_container_app.this["client"].ingress[0].fqdn, null)
}

output "client_url" {
  description = "HTTPS URL of the externally available client application."
  value       = try("https://${azurerm_container_app.this["client"].ingress[0].fqdn}", null)
}

output "gateway_fqdn" {
  description = "Internal ingress FQDN of the gateway Container App."
  value       = try(azurerm_container_app.this["gateway"].ingress[0].fqdn, null)
}

output "database_migrations_job_id" {
  description = "Resource ID of the PostgreSQL database migrations Container Apps Job."
  value       = azurerm_container_app_job.database_migrations.id
}

output "database_migrations_job_name" {
  description = "Name of the PostgreSQL database migrations Container Apps Job."
  value       = azurerm_container_app_job.database_migrations.name
}
