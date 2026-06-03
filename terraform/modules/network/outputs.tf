# ========================================
# Networking Outputs
# ========================================

output "vnets" {
  description = "Virtual Network details"
  value = {
    for name, vnet in azurerm_virtual_network.vnet : name => {
      id            = vnet.id
      name          = vnet.name
      address_space = vnet.address_space
    }
  }
}

output "subnets" {
  description = "Subnet details by VNET and subnet name"
  value = {
    for key, subnet in azurerm_subnet.subnet : key => {
      id               = subnet.id
      name             = subnet.name
      address_prefixes = subnet.address_prefixes
      vnet_name        = subnet.virtual_network_name
    }
  }
}

output "network_security_groups" {
  description = "NSG details mapped by subnet"
  value = {
    for key, nsg in azurerm_network_security_group.nsg : key => {
      id   = nsg.id
      name = nsg.name
    }
  }
}

output "bastion_host_id" {
  description = "ID of the Bastion Host"
  value       = azurerm_bastion_host.bastion.id
}

output "bastion_host_name" {
  description = "Name of the Bastion Host"
  value       = azurerm_bastion_host.bastion.name
}

output "bastion_public_ip" {
  description = "Public IP of the Bastion Host"
  value       = azurerm_public_ip.bastion_pip.ip_address
}

output "bastion_public_ip_id" {
  description = "ID of the Bastion Host's public IP"
  value       = azurerm_public_ip.bastion_pip.id
}

# ========================================
# Subnet IDs (for consuming modules)
# ========================================

output "app_subnet_id" {
  description = "ID of the application subnet"
  value       = azurerm_subnet.subnet["dev-vnet-app-subnet"].id
}

output "pe_subnet_id" {
  description = "ID of the private-endpoint subnet"
  value       = azurerm_subnet.subnet["dev-vnet-pe-subnet"].id
}

# ========================================
# Network Interfaces (consumed by VM module)
# ========================================

output "linux_nic_id" {
  description = "ID of the Linux VM network interface"
  value       = azurerm_network_interface.nic.id
}

output "linux_nic_private_ip" {
  description = "Private IP of the Linux VM network interface"
  value       = azurerm_network_interface.nic.private_ip_address
}

output "db_nic_id" {
  description = "ID of the Database VM network interface"
  value       = azurerm_network_interface.db_nic.id
}

output "db_nic_private_ip" {
  description = "Private IP of the Database VM network interface"
  value       = azurerm_network_interface.db_nic.private_ip_address
}

# ========================================
# VM Public IPs (consumed by VM/root outputs)
# ========================================

output "linux_vm_public_ip" {
  description = "Public IP address of the Linux VM"
  value       = azurerm_public_ip.vm_pip.ip_address
}

output "linux_vm_public_ip_id" {
  description = "ID of the Linux VM public IP"
  value       = azurerm_public_ip.vm_pip.id
}

output "linux_vm_fqdn" {
  description = "FQDN of the Linux VM public IP"
  value       = azurerm_public_ip.vm_pip.fqdn
}

output "db_vm_public_ip" {
  description = "Public IP address of the Database VM"
  value       = azurerm_public_ip.db_vm_pip.ip_address
}

output "db_vm_public_ip_id" {
  description = "ID of the Database VM public IP"
  value       = azurerm_public_ip.db_vm_pip.id
}

# ========================================
# Private DNS Zones (consumed by private-endpoints)
# ========================================

output "vault_dns_zone_id" {
  description = "ID of the Key Vault private DNS zone"
  value       = azurerm_private_dns_zone.vault.id
}

output "sql_dns_zone_id" {
  description = "ID of the SQL private DNS zone"
  value       = azurerm_private_dns_zone.sql_dns.id
}

output "vault_dns_link_id" {
  description = "ID of the Key Vault DNS vnet link"
  value       = azurerm_private_dns_zone_virtual_network_link.vault_link.id
}

output "sql_dns_link_id" {
  description = "ID of the SQL DNS vnet link"
  value       = azurerm_private_dns_zone_virtual_network_link.sql_dns_link.id
}