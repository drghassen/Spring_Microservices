output "postgresql_server_id" {
  description = "Resource ID of the PostgreSQL Flexible Server."
  value       = azurerm_postgresql_flexible_server.this.id
}

output "postgresql_server_fqdn" {
  description = "FQDN of the PostgreSQL Flexible Server; no credentials are exposed."
  value       = azurerm_postgresql_flexible_server.this.fqdn
}

output "postgresql_database_name" {
  description = "Name of the PostgreSQL database required by the relational services."
  value       = azurerm_postgresql_flexible_server_database.steam.name
}

output "cosmos_mongodb_account_id" {
  description = "Resource ID of the Azure Cosmos DB API for MongoDB account."
  value       = azurerm_cosmosdb_account.mongodb.id
}
