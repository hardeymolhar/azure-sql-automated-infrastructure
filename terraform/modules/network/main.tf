



resource "azurerm_private_dns_zone" "vault" {
  name                = "privatelink.vaultcore.azure.net"
  resource_group_name = var.primary_rg  
}

resource "azurerm_private_dns_zone_virtual_network_link" "vault_link" {
  name                  = "vault-dns-link"
  resource_group_name   = var.primary_rg
  private_dns_zone_name = azurerm_private_dns_zone.vault.name
  virtual_network_id    = azurerm_virtual_network.vnet["dev-vnet"].id
}

resource "azurerm_private_dns_zone" "vm_dns" {
  name                = "internal.local"
  resource_group_name = var.primary_rg


}

resource "azurerm_private_dns_zone_virtual_network_link" "vm_dns_link" {
  name                  = "vm-dns-link"
  resource_group_name   = var.primary_rg
  private_dns_zone_name = azurerm_private_dns_zone.vm_dns.name
  virtual_network_id    = azurerm_virtual_network.vnet["dev-vnet"].id

  registration_enabled = true
}


resource "azurerm_private_dns_zone" "sql_dns" {
  name                = "privatelink.database.windows.net"
  resource_group_name = var.primary_rg
}

resource "azurerm_private_dns_zone_virtual_network_link" "sql_dns_link" {
  name                  = "sql-dns-link"
  resource_group_name   = var.primary_rg
  private_dns_zone_name = azurerm_private_dns_zone.sql_dns.name
  virtual_network_id    = azurerm_virtual_network.vnet["dev-vnet"].id

}



# NIC
resource "azurerm_network_interface" "nic" {
  name                = "vm--nic"
  location            = var.primary_location
  resource_group_name = var.primary_rg

  ip_configuration {
    name                          = "ipconfig"
    subnet_id                     = azurerm_subnet.subnet["dev-vnet-app-subnet"].id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.vm_pip.id

  }
}


# NIC
resource "azurerm_network_interface" "db_nic" {
  name                = "db-nic"
  location            = var.primary_location
  resource_group_name = var.primary_rg

  ip_configuration {
    name                          = "ipconfig"
    subnet_id                     = azurerm_subnet.subnet["dev-vnet-app-subnet"].id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.db_vm_pip.id

  }
}



# =====================================================
# VM Public IPs
# =====================================================

resource "azurerm_public_ip" "vm_pip" {
  name                = "pip-linux-vm-eastus"
  location            = var.primary_location
  resource_group_name = var.primary_rg
  allocation_method   = "Static"
  sku                 = "Standard"
}



resource "azurerm_public_ip" "db_vm_pip" {
  name                = "pip-db-vm-eastus"
  location            = var.primary_location
  resource_group_name = var.primary_rg
  allocation_method   = "Static"
  sku                 = "Standard"
}

resource "azurerm_network_security_group" "nsg" {

  for_each = {
    for subnet in local.subnets :
    "${subnet.vnet_name}-${subnet.subnet_name}" => subnet
    if subnet.subnet_name != "AzureBastionSubnet"
  }

  name                = "${each.value.vnet_name}-${each.value.subnet_name}-nsg"
  location            = var.primary_location
  resource_group_name = var.primary_rg
}

resource "azurerm_subnet_network_security_group_association" "nsg_assoc" {

  for_each = {
    for subnet in local.subnets :
    "${subnet.vnet_name}-${subnet.subnet_name}" => subnet
    if subnet.subnet_name != "AzureBastionSubnet"
  }

  subnet_id = azurerm_subnet.subnet[
    "${each.value.vnet_name}-${each.value.subnet_name}"
  ].id

  network_security_group_id = azurerm_network_security_group.nsg[
    "${each.value.vnet_name}-${each.value.subnet_name}"
  ].id
}



#########################################
# NSG RULES (SCALABLE)
##########################################

# resource "azurerm_network_security_rule" "rules" {

#  for_each = var.nsg_rule_matrix
#
#  name = "${each.value.rule.name}-${each.value.nsg_key}"
#
#  priority = each.value.rule.priority
#
#  direction = "Inbound"
#  access    = "Allow"
#  protocol  = "Tcp"
#
#  source_port_range      = "*"
#  destination_port_range = tostring(each.value.rule.port)
#
#  source_address_prefixes    = [local.client_ip]
#  destination_address_prefix = "*"
#
#  resource_group_name         = var.primary_rg
#  network_security_group_name = each.value.nsg.name
#}


resource "azurerm_application_security_group" "asg" {
  name                = "vm-asg"
  location            = var.primary_location
  resource_group_name = var.primary_rg

  tags = {
    environment = "dev"
  }
}



resource "azurerm_network_interface_application_security_group_association" "asg_assoc" {
  network_interface_id          = azurerm_network_interface.nic.id
  application_security_group_id = azurerm_application_security_group.asg.id
}

resource "azurerm_network_security_rule" "rules" {

  for_each = local.nsg_rule_matrix

  name     = "${each.value.rule.name}-${each.value.nsg_key}"
  priority = each.value.rule.priority

  direction = each.value.rule.direction != null ? each.value.rule.direction : "Inbound"

  access   = "Allow"
  protocol = "Tcp"

  source_port_range      = "*"
  destination_port_range = tostring(each.value.rule.port)

  # ✅ FIX SOURCE
  source_address_prefix = lookup(local.cidr_map, each.value.rule.source, null)


  # ✅ FIX DESTINATION
  destination_address_prefix = lookup(local.cidr_map, each.value.rule.destination, null)

  resource_group_name         = var.primary_rg
  network_security_group_name = each.value.nsg.name
}
