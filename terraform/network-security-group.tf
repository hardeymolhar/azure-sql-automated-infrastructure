resource "azurerm_network_security_group" "nsg" {

  for_each = {
    for subnet in local.subnets :
    "${subnet.vnet_name}-${subnet.subnet_name}" => subnet
    if subnet.subnet_name != "AzureBastionSubnet"
  }

  name                = "${each.value.vnet_name}-${each.value.subnet_name}-nsg"
  location            = local.primary_location
  resource_group_name = local.primary_rg
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



resource "azurerm_network_security_rule" "ssh_rule" {

  for_each = {
    for key, value in azurerm_network_security_group.nsg :
    key => value
    if !strcontains(key, "pe-subnet") && !strcontains(key, "AzureBastionSubnet")
  }

  name      = "AllowSSH"
  priority  = 100
  direction = "Inbound"
  access    = "Allow"
  protocol  = "Tcp"

  source_port_range      = "*"
  destination_port_range = "22"

  source_address_prefixes    = [local.client_ip]
  destination_address_prefix = "*"

  resource_group_name         = local.primary_rg
  network_security_group_name = each.value.name
}





resource "azurerm_network_security_rule" "rdp_rule" {

  for_each = {
    for key, value in azurerm_network_security_group.nsg :
    key => value
    if !strcontains(key, "pe-subnet") && !strcontains(key, "AzureBastionSubnet")
  }

  name      = "AllowRDP"
  priority  = 120
  direction = "Inbound"
  access    = "Allow"
  protocol  = "Tcp"

  source_port_range      = "*"
  destination_port_range = "3389"

  source_address_prefixes    = [local.client_ip]
  destination_address_prefix = "*"

  resource_group_name         = local.primary_rg
  network_security_group_name = each.value.name
}




resource "azurerm_network_security_rule" "winrm_rule" {

  for_each = {
    for key, value in azurerm_network_security_group.nsg :
    key => value
    if !strcontains(key, "pe-subnet") && !strcontains(key, "AzureBastionSubnet")
  }

  name      = "AllowWinRM"
  priority  = 110
  direction = "Inbound"
  access    = "Allow"
  protocol  = "Tcp"

  source_port_range      = "*"
  destination_port_range = "5986"

  source_address_prefixes    = [local.client_ip]
  destination_address_prefix = "*"

  resource_group_name         = local.primary_rg
  network_security_group_name = each.value.name
}
 


 
resource "azurerm_network_security_rule" "winrm_rule" {

  for_each = {
    for key, value in azurerm_network_security_group.nsg :
    key => value
    if !strcontains(key, "pe-subnet") && !strcontains(key, "AzureBastionSubnet")
  }

  name      = "AllowWinRMS"
  priority  = 130
  direction = "Inbound"
  access    = "Allow"
  protocol  = "Tcp"

  source_port_range      = "*"
  destination_port_range = "5985"

  source_address_prefixes    = [local.client_ip]
  destination_address_prefix = "*"

  resource_group_name         = local.primary_rg
  network_security_group_name = each.value.name
}
 

 resource "azurerm_network_security_rule" "winrm_rule" {

  for_each = {
    for key, value in azurerm_network_security_group.nsg :
    key => value
    if !strcontains(key, "pe-subnet") && !strcontains(key, "AzureBastionSubnet")
  }

  name      = "AllowWinRMS"
  priority  = 130
  direction = "Inbound"
  access    = "Allow"
  protocol  = "Tcp"

  source_port_range      = "*"
  destination_port_range = "1433"

  source_address_prefixes    = [local.client_ip]
  destination_address_prefix = "*"

  resource_group_name         = local.primary_rg
  network_security_group_name = each.value.name
}
 