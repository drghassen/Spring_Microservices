resource "azurerm_private_dns_zone" "postgresql" {
  name                = "privatelink.postgres.database.azure.com"
  resource_group_name = var.resource_group_name
  tags                = var.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "postgresql" {
  name                  = "${var.name_prefix}-postgresql-dns-link"
  resource_group_name   = var.resource_group_name
  private_dns_zone_name = azurerm_private_dns_zone.postgresql.name
  virtual_network_id    = var.virtual_network_id
  registration_enabled  = false
  tags                  = var.tags
}

resource "azurerm_postgresql_flexible_server" "this" {
  name                = "${var.name_prefix}-postgresql"
  resource_group_name = var.resource_group_name
  location            = var.location
  zone                = "1"

  version                       = "16"
  delegated_subnet_id           = var.postgresql_delegated_subnet_id
  private_dns_zone_id           = azurerm_private_dns_zone.postgresql.id
  administrator_login           = var.postgresql_administrator_login
  administrator_password        = var.postgresql_administrator_password
  sku_name                      = "B_Standard_B1ms"
  storage_mb                    = 32768
  backup_retention_days         = 7
  geo_redundant_backup_enabled  = false
  public_network_access_enabled = false
  tags                          = var.tags

  depends_on = [azurerm_private_dns_zone_virtual_network_link.postgresql]
}

resource "azurerm_postgresql_flexible_server_database" "steam" {
  name      = "steam"
  server_id = azurerm_postgresql_flexible_server.this.id
  charset   = "UTF8"
  collation = "en_US.utf8"
}

resource "azurerm_cosmosdb_account" "mongodb" {
  name                 = "${var.name_prefix}-mongodb"
  location             = var.location
  resource_group_name  = var.resource_group_name
  offer_type           = "Standard"
  kind                 = "MongoDB"
  mongo_server_version = "4.2"

  automatic_failover_enabled    = false
  public_network_access_enabled = true

  consistency_policy {
    consistency_level = "Session"
  }

  capabilities {
    name = "EnableMongo"
  }

  capabilities {
    name = "EnableServerless"
  }

  geo_location {
    location          = var.location
    failover_priority = 0
  }

  tags = var.tags
}

resource "azurerm_cosmosdb_mongo_database" "users" {
  name                = "users"
  resource_group_name = var.resource_group_name
  account_name        = azurerm_cosmosdb_account.mongodb.name
}

resource "azurerm_cosmosdb_mongo_collection" "users" {
  name                = "userApp"
  resource_group_name = var.resource_group_name
  account_name        = azurerm_cosmosdb_account.mongodb.name
  database_name       = azurerm_cosmosdb_mongo_database.users.name

  index {
    keys = ["_id"]
  }

  index {
    keys   = ["username"]
    unique = true
  }
}

resource "azurerm_cosmosdb_mongo_database" "library" {
  name                = "library"
  resource_group_name = var.resource_group_name
  account_name        = azurerm_cosmosdb_account.mongodb.name
}

resource "azurerm_cosmosdb_mongo_collection" "library" {
  name                = "libraryApp"
  resource_group_name = var.resource_group_name
  account_name        = azurerm_cosmosdb_account.mongodb.name
  database_name       = azurerm_cosmosdb_mongo_database.library.name

  index {
    keys = ["_id"]
  }

  index {
    keys   = ["username"]
    unique = true
  }
}
