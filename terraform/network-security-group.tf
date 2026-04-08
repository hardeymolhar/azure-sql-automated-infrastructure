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
#########################################
resource "azurerm_network_security_rule" "rules" {

  for_each = local.nsg_rule_matrix

  name = "${each.value.rule.name}-${each.value.nsg_key}"

  priority = each.value.rule.priority

  direction = "Inbound"
  access    = "Allow"
  protocol  = "Tcp"

  source_port_range      = "*"
  destination_port_range = tostring(each.value.rule.port)

  source_address_prefixes    = [local.client_ip]
  destination_address_prefix = "*"

  resource_group_name         = local.primary_rg
  network_security_group_name = each.value.nsg.name
}



  
  
#  resource "azurerm_network_security_rule" "rules" {
#
#  for_each = local.nsg_rule_matrix
#
#  name     = "${each.value.rule.name}-${each.value.nsg_key}"
#  priority = each.value.rule.priority
#
#  direction = each.value.rule.port == 1433 ? "Outbound" : "Inbound"
#
#  access   = "Allow"
#  protocol = "Tcp"
#
#  source_port_range      = "*"
#  destination_port_range = tostring(each.value.rule.port)
#
#  source_address_prefixes = each.value.rule.port == 1433 ? ["*"] : [local.client_ip]
#
#  destination_address_prefix = each.value.rule.port == 1433 ? "VirtualNetwork" : "*"
#
#  resource_group_name         = local.primary_rg
#  network_security_group_name = each.value.nsg.name
#}
