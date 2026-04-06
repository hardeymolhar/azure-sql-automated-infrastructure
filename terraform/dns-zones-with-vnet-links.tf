
resource "azurerm_private_dns_zone" "vault" {
  name                = "privatelink.vaultcore.azure.net"
  resource_group_name = local.primary_rg
}

resource "azurerm_private_dns_zone_virtual_network_link" "vault_link" {
  name                  = "vault-dns-link"
  resource_group_name   = local.primary_rg
  private_dns_zone_name = azurerm_private_dns_zone.vault.name
  virtual_network_id    = azurerm_virtual_network.vnet["dev-vnet"].id
}

resource "azurerm_private_dns_zone" "vm_dns" {
  name                = "internal.local"
  resource_group_name = local.primary_rg


}

resource "azurerm_private_dns_zone_virtual_network_link" "vm_dns_link" {
  name                  = "vm-dns-link"
  resource_group_name   = local.primary_rg
  private_dns_zone_name = azurerm_private_dns_zone.vm_dns.name
  virtual_network_id    = azurerm_virtual_network.vnet["dev-vnet"].id

  registration_enabled = true
}


resource "azurerm_private_dns_zone" "sql_dns" {
  name                = "privatelink.database.windows.net"
  resource_group_name = local.primary_rg
}

resource "azurerm_private_dns_zone_virtual_network_link" "sql_dns_link" {
  name                  = "sql-dns-link"
  resource_group_name   = local.primary_rg
  private_dns_zone_name = azurerm_private_dns_zone.sql_dns.name
  virtual_network_id    = azurerm_virtual_network.vnet["dev-vnet"].id

}
