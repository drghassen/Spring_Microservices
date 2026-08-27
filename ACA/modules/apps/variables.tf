variable "resource_group_name" {
  description = "Name of the Resource Group that contains the Container Apps."
  type        = string
}

variable "container_app_environment_id" {
  description = "ID of the existing Azure Container Apps environment."
  type        = string
}

variable "container_app_environment_default_domain" {
  description = "Default domain of the existing Azure Container Apps environment."
  type        = string
}

variable "apps_managed_identity_id" {
  description = "Resource ID of the existing user-assigned identity used by every Container App."
  type        = string
}

variable "acr_login_server" {
  description = "Login server of the existing Azure Container Registry."
  type        = string
}

variable "application_image_digests" {
  description = "Immutable ACR digests for all application images."
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
  description = "Applications allowed to use their normal minimum replica counts; resource declarations never depend on this set."
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

variable "postgresql_server_fqdn" {
  description = "FQDN of the existing PostgreSQL Flexible Server."
  type        = string
}

variable "postgresql_database_name" {
  description = "Name of the existing PostgreSQL database used by the relational services."
  type        = string
}

variable "postgresql_application_username" {
  description = "Required PostgreSQL application username, distinct from the PostgreSQL administrator account."
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

variable "cosmos_mongodb_uri" {
  description = "Required MongoDB connection URI for the existing Cosmos DB MongoDB account."
  type        = string
  sensitive   = true
}

variable "application_jwt_secret" {
  description = "Required JWT secret consumed through Container App secret references."
  type        = string
  sensitive   = true
}

variable "application_admin_password" {
  description = "Required application administrator password consumed through a Container App secret reference."
  type        = string
  sensitive   = true
}

variable "tags" {
  description = "Tags applied to all Container Apps."
  type        = map(string)
}

variable "location" {
  description = "Azure region where the resources are deployed."
  type        = string
}

variable "postgresql_administrator_login" {
  description = "Administrator login for PostgreSQL Flexible Server."
  type        = string
  sensitive   = true

  validation {
    condition     = can(regex("^[a-z_][a-z0-9_]{0,62}$", var.postgresql_administrator_login)) && !startswith(var.postgresql_administrator_login, "pg_")
    error_message = "postgresql_administrator_login must be a safe lowercase PostgreSQL identifier and must not begin with pg_."
  }
}

variable "postgresql_administrator_password" {
  description = "Administrator password for PostgreSQL Flexible Server."
  type        = string
  sensitive   = true
}
