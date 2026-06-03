
# ========================================
# Linux Virtual Machine Outputs
# ========================================

output "linux_vm_id" {
  description = "ID of the Linux VM"
  value       = azurerm_linux_virtual_machine.vm[0].id
}

output "linux_vm_name" {
  description = "Name of the Linux VM"
  value       = azurerm_linux_virtual_machine.vm[0].name
}

output "linux_vm_principal_id" {
  description = "Principal ID of Linux VM's managed identity"
  value       = azurerm_linux_virtual_machine.vm[0].identity[0].principal_id
}

# ========================================
# Database Virtual Machine Outputs
# ========================================

output "db_vm_ids" {
  description = "IDs of the Windows Database VMs"
  value       = azurerm_windows_virtual_machine.db_vm[*].id
}

output "db_vm_names" {
  description = "Names of the Windows Database VMs"
  value       = azurerm_windows_virtual_machine.db_vm[*].name
}

output "db_vm_zones" {
  description = "Availability zones of the Windows Database VMs"
  value       = azurerm_windows_virtual_machine.db_vm[*].zone
}

output "db_vm_principal_ids" {
  description = "Principal IDs of Database VMs' managed identities"
  value       = azurerm_windows_virtual_machine.db_vm[*].identity[0].principal_id
}


# ========================================
# Database Managed Disks Outputs
# ========================================

output "data_disk_ids" {
  description = "IDs of all data disks"
  value       = azurerm_managed_disk.db_data_disk[*].id
}

output "data_disk_names" {
  description = "Names of all data disks"
  value       = azurerm_managed_disk.db_data_disk[*].name
}

output "log_disk_ids" {
  description = "IDs of all log disks"
  value       = azurerm_managed_disk.db_log_disk[*].id
}

output "log_disk_names" {
  description = "Names of all log disks"
  value       = azurerm_managed_disk.db_log_disk[*].name
}

output "data_disk_count" {
  description = "Total number of Windows data disks"
  value       = length(azurerm_managed_disk.db_data_disk)
}

output "log_disk_count" {
  description = "Total number of Windows log disks"
  value       = length(azurerm_managed_disk.db_log_disk)
}

output "disk_attachment_details" {
  description = "Data disk attachment mapping"
  value = {
    data_disk_lun_start = local.data_lun_start
    log_disk_lun_start  = local.log_lun_start
    data_disks_per_vm   = var.data_disks_per_vm
    log_disks_per_vm    = var.log_disks_per_vm
  }
}
