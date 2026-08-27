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

variable "postgresql_subnet_address_prefix" {
  description = "CIDR prefix dedicated exclusively to Azure Database for PostgreSQL Flexible Server."
  type        = string
  default     = "10.80.3.0/28"
}

variable "postgresql_administrator_login" {
  description = "Administrator login for the PostgreSQL Flexible Server. Supply it through TF_VAR_postgresql_administrator_login or an ignored local tfvars file."
  type        = string
  sensitive   = true

  validation {
    condition     = can(regex("^[a-z_][a-z0-9_]{0,62}$", var.postgresql_administrator_login)) && !startswith(var.postgresql_administrator_login, "pg_")
    error_message = "postgresql_administrator_login must be a safe lowercase PostgreSQL identifier and must not begin with pg_."
  }
}

variable "postgresql_administrator_password" {
  description = "Administrator password for the PostgreSQL Flexible Server. Supply it only through TF_VAR_postgresql_administrator_password or an ignored local tfvars file."
  type        = string
  sensitive   = true

  validation {
    condition     = length(var.postgresql_administrator_password) >= 8 && length(var.postgresql_administrator_password) <= 128
    error_message = "postgresql_administrator_password must contain 8-128 characters."
  }
}

variable "application_image_digests" {
  description = "Immutable ACR digests for all nine application images, keyed by application name."
  type        = map(string)

  validation {
    condition = toset(keys(var.application_image_digests)) == toset([
      "client",
      "config-server",
      "discovery-service",
      "gateway",
      "games-service",
      "library-service",
      "order-service",
      "payment-service",
      "user-service"
      ]) && alltrue([
      for digest in values(var.application_image_digests) : can(regex("^sha256:[0-9a-f]{64}$", digest))
    ])
    error_message = "application_image_digests must contain exactly the nine known applications with valid sha256 digests."
  }
}

variable "database_migrations_image_digest" {
  description = "Immutable ACR digest for the PostgreSQL migration image."
  type        = string

  validation {
    condition     = can(regex("^sha256:[0-9a-f]{64}$", var.database_migrations_image_digest))
    error_message = "database_migrations_image_digest must be a valid sha256 digest."
  }
}

variable "active_applications" {
  description = "Applications allowed to keep their normal minimum replicas. All applications remain declared; the default activates all nine."
  type        = set(string)
  default = [
    "client",
    "config-server",
    "discovery-service",
    "gateway",
    "games-service",
    "library-service",
    "order-service",
    "payment-service",
    "user-service"
  ]

  validation {
    condition = alltrue([
      for app in var.active_applications : contains([
        "client",
        "config-server",
        "discovery-service",
        "gateway",
        "games-service",
        "library-service",
        "order-service",
        "payment-service",
        "user-service"
      ], app)
    ])
    error_message = "active_applications must only contain known application names."
  }
}

variable "postgresql_application_username" {
  description = "Required PostgreSQL application username, distinct from the administrator account."
  type        = string

  validation {
    condition     = can(regex("^[a-z_][a-z0-9_]{0,62}$", var.postgresql_application_username)) && !startswith(var.postgresql_application_username, "pg_")
    error_message = "postgresql_application_username must be a safe lowercase PostgreSQL identifier and must not begin with pg_."
  }
}

variable "postgresql_application_password" {
  description = "Required PostgreSQL application password."
  type        = string
  sensitive   = true
}

variable "application_jwt_secret" {
  description = "Required JWT secret for Azure Container Apps."
  type        = string
  sensitive   = true
}

variable "application_admin_password" {
  description = "Required application administrator password."
  type        = string
  sensitive   = true
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
