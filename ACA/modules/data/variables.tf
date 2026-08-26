variable "resource_group_name" {
  description = "Name of the existing Resource Group that contains the data resources."
  type        = string
}

variable "location" {
  description = "Azure region for the data resources."
  type        = string
}

variable "name_prefix" {
  description = "Prefix used to name data resources."
  type        = string
}

variable "tags" {
  description = "Tags applied to data resources."
  type        = map(string)
}

variable "virtual_network_id" {
  description = "ID of the existing ACA virtual network linked to PostgreSQL private DNS."
  type        = string
}

variable "postgresql_delegated_subnet_id" {
  description = "ID of the dedicated subnet delegated to PostgreSQL Flexible Server."
  type        = string
}

variable "postgresql_administrator_login" {
  description = "Administrator login for the PostgreSQL Flexible Server."
  type        = string
  sensitive   = true
}

variable "postgresql_administrator_password" {
  description = "Administrator password for the PostgreSQL Flexible Server."
  type        = string
  sensitive   = true
}
