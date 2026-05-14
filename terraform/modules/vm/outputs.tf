
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

output "linux_vm_private_ip" {
  description = "Private IP of the Linux VM"
  value       = azurerm_network_interface.nic.private_ip_address
}

output "linux_vm_public_ip" {
  description = "Public IP of the Linux VM"
  value       = azurerm_public_ip.vm_pip.ip_address
}

output "linux_vm_public_ip_id" {
  description = "ID of the Linux VM public IP"
  value       = azurerm_public_ip.vm_pip.id
}

output "linux_vm_fqdn" {
  description = "FQDN of the Linux VM (if applicable)"
  value       = azurerm_public_ip.vm_pip.fqdn
}

output "linux_vm_principal_id" {
  description = "Principal ID of Linux VM's managed identity"
  value       = azurerm_linux_virtual_machine.vm[0].identity[0].principal_id
}

output "linux_nic_id" {
  description = "ID of the Linux VM's network interface"
  value       = azurerm_network_interface.nic.id
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

output "db_vm_private_ips" {
  description = "Private IPs of the Windows Database VMs"
  value       = azurerm_network_interface.db_nic.private_ip_address
}

output "db_vm_public_ip" {
  description = "Public IP of the Database VM"
  value       = azurerm_public_ip.db_vm_pip.ip_address
}

output "db_vm_public_ip_id" {
  description = "ID of the Database VM public IP"
  value       = azurerm_public_ip.db_vm_pip.id
}

output "db_vm_principal_ids" {
  description = "Principal IDs of Database VMs' managed identities"
  value       = azurerm_windows_virtual_machine.db_vm[*].identity[0].principal_id
}

output "db_nic_id" {
  description = "ID of the Database VM's network interface"
  value       = azurerm_network_interface.db_nic.id
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

output "disk_attachment_details" {
  description = "Data disk attachment mapping"
  value = {
    data_disk_lun_start = local.data_lun_start
    log_disk_lun_start  = local.log_lun_start
    data_disks_per_vm   = var.data_disks_per_vm
    log_disks_per_vm    = var.log_disks_per_vm
  }
}