# ========================================
# Key Vault Outputs
# ========================================

output "key_vault_id" {
  description = "ID of the Key Vault"
  value       = azurerm_key_vault.kv.id
}

output "key_vault_name" {
  description = "Name of the Key Vault"
  value       = azurerm_key_vault.kv.name
}

output "key_vault_uri" {
  description = "URI of the Key Vault"
  value       = azurerm_key_vault.kv.vault_uri
}

output "sql_tde_key_id" {
  description = "ID of the Key Vault key used for SQL TDE"
  value       = azurerm_key_vault_key.sql_key.id
}
