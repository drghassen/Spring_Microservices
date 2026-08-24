# The Resource Group is owned outside this stack and is intentionally read-only.
# This root module remains resource-free until the ACA architecture is approved.
data "azurerm_resource_group" "current" {
  name = var.resource_group_name
}

# The registry is owned outside this stack and is intentionally read-only.
data "azurerm_container_registry" "current" {
  name                = var.acr_name
  resource_group_name = var.resource_group_name
}

# No image is selected at the foundation stage. Future Container Apps must
# use immutable CircleCI-produced image tags; legacy build-31 images are not
# valid deployment inputs.
