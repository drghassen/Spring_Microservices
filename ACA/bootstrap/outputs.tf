output "state_storage_account_name" {
  description = "Name of the Storage Account dedicated to Terraform state."
  value       = azurerm_storage_account.terraform_state.name
}

output "state_storage_account_id" {
  description = "Azure resource ID of the Terraform state Storage Account."
  value       = azurerm_storage_account.terraform_state.id
}

output "state_container_name" {
  description = "Private Blob container that will contain Terraform state."
  value       = azurerm_storage_container.terraform_state.name
}

output "state_blob_endpoint" {
  description = "Blob endpoint of the Terraform state Storage Account."
  value       = azurerm_storage_account.terraform_state.primary_blob_endpoint
}