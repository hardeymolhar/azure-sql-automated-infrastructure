# ====================================
# Private Endpoint + DNS For Key Vault
# ====================================

resource "azurerm_private_endpoint" "dbvk_pe" {
  name                = "pev-prod-vault"
  resource_group_name = var.primary_rg
  location            = var.primary_location
  subnet_id           = var.pe_subnet_id

  private_service_connection {
    name                           = "psc-vault"
    private_connection_resource_id = var.key_vault_id
    subresource_names              = ["vault"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name = "keyvault-dns-group"

    private_dns_zone_ids = [
      var.vault_dns_zone_id
    ]
  }
}


# ====================================
# Private Endpoint  For Azure SQL Primary
# ====================================

resource "azurerm_private_endpoint" "azuresql_pe" {
  name                = "pev-prod-sql"
  resource_group_name = var.primary_rg
  location            = var.primary_location
  subnet_id           = var.pe_subnet_id

  private_service_connection {
    name                           = "sql-connection"
    private_connection_resource_id = var.sql_server_id
    subresource_names              = ["sqlServer"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name = "azuresql-dns-group"

    private_dns_zone_ids = [
      var.sql_dns_zone_id
    ]
  }
}
