variable "subscription_id" {
  description = "Azure subscription ID used by Terraform. Provide it through TF_VAR_subscription_id or a local, ignored tfvars file."
  type        = string

  validation {
    condition     = can(regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$", var.subscription_id))
    error_message = "subscription_id must be a valid Azure subscription UUID."
  }
}

variable "resource_group_name" {
  description = "Name of the existing Azure Resource Group used by the ACA foundation."
  type        = string
  default     = "internship_proxym"

  validation {
    condition     = length(trimspace(var.resource_group_name)) > 0
    error_message = "resource_group_name must not be empty."
  }
}

variable "acr_name" {
  description = "Name of the existing Azure Container Registry used as the image source."
  type        = string
  default     = "ghassenspringservices"

  validation {
    condition     = length(var.acr_name) >= 5 && length(var.acr_name) <= 50 && can(regex("^[a-z0-9]+$", var.acr_name))
    error_message = "acr_name must be 5-50 characters and contain only lowercase letters and digits."
  }
}

variable "project_name" {
  description = "Short project name used for Azure resource naming."
  type        = string
  default     = "ghassen-dridi"

  validation {
    condition     = length(var.project_name) >= 2 && length(var.project_name) <= 24 && can(regex("^[a-z0-9]([a-z0-9-]*[a-z0-9])?$", var.project_name))
    error_message = "project_name must be 2-24 characters, lowercase, and contain only letters, digits, or internal hyphens."
  }
}

variable "environment" {
  description = "Deployment environment name."
  type        = string
  default     = "aca"

  validation {
    condition     = length(trimspace(var.environment)) > 0 && can(regex("^[a-z0-9]([a-z0-9-]*[a-z0-9])?$", var.environment))
    error_message = "environment must be non-empty and contain only lowercase letters, digits, or internal hyphens."
  }
}

variable "tags" {
  description = "Additional Azure resource tags merged with the foundation defaults."
  type        = map(string)
  default     = {}
}

variable "vnet_address_space" {
  description = "CIDR address space for the ACA virtual network."
  type        = list(string)
  default     = ["10.80.0.0/16"]
}

variable "aca_infrastructure_subnet_address_prefix" {
  description = "CIDR prefix dedicated exclusively to Azure Container Apps infrastructure."
  type        = string
  default     = "10.80.0.0/23"
}

variable "private_endpoints_subnet_address_prefix" {
  description = "CIDR prefix reserved for future PostgreSQL, Cosmos DB, and Key Vault private endpoints."
  type        = string
  default     = "10.80.2.0/24"
}

variable "log_analytics_retention_in_days" {
  description = "Number of days to retain Log Analytics Workspace data."
  type        = number
  default     = 30

  validation {
    condition     = var.log_analytics_retention_in_days >= 30 && var.log_analytics_retention_in_days <= 730
    error_message = "log_analytics_retention_in_days must be between 30 and 730 days."
  }
}
