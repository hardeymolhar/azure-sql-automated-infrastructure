# =====================================================
# IaaS SQL-on-VM track — module outputs (null when iaas_enabled = false)
# =====================================================

output "iaas_storage_account_name" {
  description = "Witness/backup storage account name (Cloud Witness quorum in configure-wsfc.yml resolves this by name)."
  value       = var.iaas_enabled ? azurerm_storage_account.iaas[0].name : null
}

output "iaas_storage_account_id" {
  description = "Witness/backup storage account id."
  value       = var.iaas_enabled ? azurerm_storage_account.iaas[0].id : null
}
