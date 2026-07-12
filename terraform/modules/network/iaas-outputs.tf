# =====================================================
# IaaS SQL-on-VM track — module outputs (null when iaas_enabled = false)
# =====================================================

output "iaas_linux_nic_id" {
  description = "NIC id of the IaaS Linux workload VM (nic-<suffix>)."
  value       = var.iaas_enabled ? azurerm_network_interface.iaas_linux[0].id : null
}

output "iaas_win_nic_id" {
  description = "NIC id of SQL Node 1 (nic-win-<suffix>)."
  value       = var.iaas_enabled ? azurerm_network_interface.iaas_win[0].id : null
}

output "iaas_win2_nic_id" {
  description = "NIC id of SQL Node 2 (nic-win2-<suffix>)."
  value       = var.iaas_enabled ? azurerm_network_interface.iaas_win2[0].id : null
}

output "iaas_dc_nic_id" {
  description = "NIC id of Domain Controller 1 (nic-dc-<suffix>, static 10.10.4.4)."
  value       = var.iaas_enabled ? azurerm_network_interface.iaas_dc[0].id : null
}

output "iaas_dc2_nic_id" {
  description = "NIC id of Domain Controller 2 (nic-dc2-<suffix>, static 10.10.4.5)."
  value       = var.iaas_enabled ? azurerm_network_interface.iaas_dc2[0].id : null
}

output "iaas_linux_vm_public_ip" {
  description = "Static public IP of the IaaS Linux VM's PIP — consumed by the security module for the Key Vault firewall (app-vm.sh:200)."
  value       = var.iaas_enabled ? azurerm_public_ip.iaas["linux"].ip_address : null
}

output "iaas_public_ips" {
  description = "Public IP addresses of the IaaS track VMs, keyed linux/win/win2/dc/dc2."
  value       = var.iaas_enabled ? { for k, pip in azurerm_public_ip.iaas : k => pip.ip_address } : null
}

output "iaas_storage_subnet_ids" {
  description = "Subnet ids allowed through the witness/backup storage firewall (storage.sh:201 — main + subnet-win)."
  value       = var.iaas_enabled ? [azurerm_subnet.iaas["win"].id, azurerm_subnet.iaas["main"].id] : []
}

output "iaas_lb_private_ip" {
  description = "AG listener VIP published by the internal LB (10.10.1.200)."
  value       = var.iaas_enabled ? local.iaas_lb_ip : null
}
