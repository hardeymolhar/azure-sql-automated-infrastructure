# ========================================
# Private Endpoint Outputs
# ========================================

output "key_vault_private_endpoint_id" {
  description = "ID of the Key Vault private endpoint"
  value       = azurerm_private_endpoint.dbvk_pe.id
}

output "key_vault_private_ip" {
  description = "Private IP of the Key Vault private endpoint"
  value       = azurerm_private_endpoint.dbvk_pe.private_service_connection[0].private_ip_address
}

output "sql_private_endpoint_id" {
  description = "ID of the Azure SQL private endpoint"
  value       = azurerm_private_endpoint.azuresql_pe.id
}

output "sql_private_ip" {
  description = "Private IP of the Azure SQL private endpoint"
  value       = azurerm_private_endpoint.azuresql_pe.private_service_connection[0].private_ip_address
}
