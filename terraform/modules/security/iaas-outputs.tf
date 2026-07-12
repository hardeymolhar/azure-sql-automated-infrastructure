# =====================================================
# IaaS SQL-on-VM track — module outputs (null when iaas_enabled = false)
# The DES outputs depends_on their Key Vault access policies so any consumer
# (the vm module's CMK disks) only sees a DES that can already wrap/unwrap —
# disk creation fails otherwise.
# =====================================================

output "iaas_key_vault_id" {
  description = "Id of the IaaS Key Vault (khv-<suffix>)."
  value       = var.iaas_enabled ? azurerm_key_vault.iaas[0].id : null
}

output "iaas_key_vault_name" {
  description = "Name of the IaaS Key Vault."
  value       = var.iaas_enabled ? azurerm_key_vault.iaas[0].name : null
}

output "iaas_windows_des_id" {
  description = "Disk Encryption Set id for the Windows SQL node disks (winsql-des-<suffix>)."
  value       = var.iaas_enabled ? azurerm_disk_encryption_set.iaas_windows[0].id : null

  depends_on = [azurerm_key_vault_access_policy.iaas_windows_des]
}

output "iaas_linux_des_id" {
  description = "Disk Encryption Set id for the Linux workload VM disks (sql-des-<suffix>)."
  value       = var.iaas_enabled ? azurerm_disk_encryption_set.iaas_linux[0].id : null

  depends_on = [azurerm_key_vault_access_policy.iaas_linux_des]
}
