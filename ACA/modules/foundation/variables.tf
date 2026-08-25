variable "resource_group_name" {
  description = "Name of the existing Resource Group that contains the foundation resources."
  type        = string
}

variable "location" {
  description = "Azure region for the foundation resources."
  type        = string
}

variable "name_prefix" {
  description = "Prefix used to name foundation resources."
  type        = string
}

variable "tags" {
  description = "Tags applied to foundation resources."
  type        = map(string)
}

variable "aca_infrastructure_subnet_id" {
  description = "ID of the subnet delegated exclusively to Azure Container Apps environments."
  type        = string
}

variable "log_analytics_retention_in_days" {
  description = "Number of days to retain Log Analytics Workspace data."
  type        = number

  validation {
    condition     = var.log_analytics_retention_in_days >= 30 && var.log_analytics_retention_in_days <= 730
    error_message = "log_analytics_retention_in_days must be between 30 and 730 days."
  }
}
