variable "resource_group_name" {
  description = "Name of the Resource Group that contains the virtual network."
  type        = string
}

variable "location" {
  description = "Azure region for the virtual network."
  type        = string
}

variable "name_prefix" {
  description = "Prefix used to name network resources."
  type        = string
}

variable "tags" {
  description = "Tags applied to taggable network resources."
  type        = map(string)
}

variable "vnet_address_space" {
  description = "Address space assigned to the virtual network."
  type        = list(string)
}

variable "aca_infrastructure_subnet_address_prefix" {
  description = "CIDR prefix reserved exclusively for Azure Container Apps infrastructure."
  type        = string
}

variable "private_endpoints_subnet_address_prefix" {
  description = "CIDR prefix reserved for future private endpoints."
  type        = string
}

variable "postgresql_subnet_address_prefix" {
  description = "CIDR prefix dedicated exclusively to PostgreSQL Flexible Server."
  type        = string
}
