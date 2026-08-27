resource "azurerm_log_analytics_workspace" "this" {
  name                = "${var.name_prefix}-law"
  location            = var.location
  resource_group_name = var.resource_group_name
  sku                 = "PerGB2018"
  retention_in_days   = var.log_analytics_retention_in_days
  tags                = var.tags

  lifecycle {
    prevent_destroy = true
  }
}

resource "azurerm_container_app_environment" "this" {
  name                           = "${var.name_prefix}-env"
  location                       = var.location
  resource_group_name            = var.resource_group_name
  infrastructure_subnet_id       = var.aca_infrastructure_subnet_id
  log_analytics_workspace_id     = azurerm_log_analytics_workspace.this.id
  internal_load_balancer_enabled = false
  tags                           = var.tags

  # This does not make any application public. Ingress will be decided later
  # per Container App; only the Angular client is expected to require external ingress.
  workload_profile {
    name                  = "Consumption"
    workload_profile_type = "Consumption"
  }

  lifecycle {
    prevent_destroy = true
  }
}
