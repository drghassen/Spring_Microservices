variable "resource_group_name" {
  description = "Name of the Resource Group that contains the managed identity."
  type        = string
}

variable "location" {
  description = "Azure region for the managed identity."
  type        = string
}

variable "name_prefix" {
  description = "Prefix used to name the managed identity."
  type        = string
}

variable "acr_id" {
  description = "Resource ID of the existing Azure Container Registry receiving the AcrPull assignment."
  type        = string
}

variable "tags" {
  description = "Tags applied to the managed identity."
  type        = map(string)
}
