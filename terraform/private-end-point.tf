

# ====================================
# Private Endpoint + DNS For Key Vault
# ====================================

resource "azurerm_private_endpoint" "dbvk_pe" {
  name                = "pev-prod-vault"
  resource_group_name = local.primary_rg
  location            = local.primary_location
  subnet_id           = azurerm_subnet.subnet["dev-vnet-pe-subnet"].id

  private_service_connection {
    name                           = "psc-vault"
    private_connection_resource_id = azurerm_key_vault.kv.id
    subresource_names              = ["vault"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name = "keyvault-dns-group"

    private_dns_zone_ids = [
      azurerm_private_dns_zone.vault.id
    ]
  }
  depends_on = [
    azurerm_private_dns_zone_virtual_network_link.vault_link
  ]
}





# ====================================
# Private Endpoint  For Azure SQL Primary
# ====================================

resource "azurerm_private_endpoint" "azuresql_pe" {
  name                = "pev-prod-sql"
  resource_group_name = local.primary_rg
  location            = local.primary_location
  subnet_id           = azurerm_subnet.subnet["dev-vnet-pe-subnet"].id

  private_service_connection {
    name                           = "sql-connection"
    private_connection_resource_id = azurerm_mssql_server.sql.id
    subresource_names              = ["sqlServer"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name = "azuresql-dns-group"

    private_dns_zone_ids = [
      azurerm_private_dns_zone.sql_dns.id
    ]
  }
  depends_on = [
    azurerm_private_dns_zone_virtual_network_link.sql_dns_link,
    azurerm_subnet.subnet["pe-subnet"]
  ]
}
