# VNet + Subnet
resource "azurerm_virtual_network" "vnet" {
  for_each = var.network_structure

  name                = each.key
  location            = local.primary_location
  resource_group_name = local.primary_rg
  address_space       = each.value.address_space
}

resource "azurerm_subnet" "subnet" {
  for_each = local.subnet_map

  name                 = each.value.subnet_name
  resource_group_name  = local.primary_rg
  virtual_network_name = azurerm_virtual_network.vnet[each.value.vnet_name].name

  address_prefixes = each.value.prefix
}