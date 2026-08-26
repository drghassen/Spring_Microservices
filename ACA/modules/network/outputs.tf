output "vnet_id" {
  description = "ID of the virtual network."
  value       = azurerm_virtual_network.this.id
}

output "vnet_name" {
  description = "Name of the virtual network."
  value       = azurerm_virtual_network.this.name
}

output "aca_infrastructure_subnet_id" {
  description = "ID of the subnet delegated to Azure Container Apps environments."
  value       = azurerm_subnet.aca_infrastructure.id
}

output "private_endpoints_subnet_id" {
  description = "ID of the subnet reserved for future private endpoints."
  value       = azurerm_subnet.private_endpoints.id
}

output "postgresql_subnet_id" {
  description = "ID of the subnet delegated to PostgreSQL Flexible Server."
  value       = azurerm_subnet.postgresql.id
}
