# outputs.tf

output "storage_account_id" {
  value = azurerm_storage_account.bootstrap.id
}

output "storage_account_name" {
  value = azurerm_storage_account.bootstrap.name
}

output "primary_connection_string" {
  value     = azurerm_storage_account.bootstrap.primary_connection_string
  sensitive = true
}