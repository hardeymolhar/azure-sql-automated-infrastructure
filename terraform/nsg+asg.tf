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



#########################################
# NSG RULES (SCALABLE)
##########################################

# resource "azurerm_network_security_rule" "rules" {

#  for_each = local.nsg_rule_matrix
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
#  resource_group_name         = local.primary_rg
#  network_security_group_name = each.value.nsg.name
#}


resource "azurerm_application_security_group" "asg" {
  name                = "vm-asg"
  location            = local.primary_location
  resource_group_name = local.primary_rg

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

  resource_group_name         = local.primary_rg
  network_security_group_name = each.value.nsg.name
}
