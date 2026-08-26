variable "subscription_id" {
  description = "Azure subscription ID used by Terraform."
  type        = string
}

variable "resource_group_name" {
  description = "Existing Resource Group that will contain Terraform state."
  type        = string
  default     = "internship_proxym"
}

variable "state_storage_account_name" {
  description = "Globally unique Storage Account name for Terraform state."
  type        = string
  default     = "stghassendridiaca5304"

  validation {
    condition     = can(regex("^[a-z0-9]{3,24}$", var.state_storage_account_name))
    error_message = "The Storage Account name must contain 3 to 24 lowercase letters or digits."
  }
}

variable "state_container_name" {
  description = "Private Blob container that stores Terraform state."
  type        = string
  default     = "tfstate"
}

variable "tags" {
  description = "Additional Azure tags."
  type        = map(string)
  default     = {}
}