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