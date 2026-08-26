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

variable "application_image_tag" {
  description = "Shared immutable ACR image tag for all application images."
  type        = string

  validation {
    condition     = var.application_image_tag != "latest"
    error_message = "application_image_tag must not be latest."
  }

  validation {
    condition     = var.application_image_tag != "build-31"
    error_message = "application_image_tag must not be build-31."
  }

  validation {
    condition     = can(regex("^build-[0-9]+$", var.application_image_tag))
    error_message = "application_image_tag must match build-<number>."
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
