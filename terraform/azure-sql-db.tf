

# Azure SQL Server
resource "azurerm_mssql_server" "sql" {
  name                         = "sqlserver123455667"
  resource_group_name          = local.primary_rg
  location                     = local.primary_location
  version                      = "12.0"
  administrator_login          = var.admin_username
  administrator_login_password = var.admin_password
}

resource "azurerm_mssql_server" "sql_secondary" {
  name                         = "whizlabserver-replica"
  resource_group_name          = local.primary_rg
  location                     = local.secondary_location
  version                      = "12.0"
  administrator_login          = var.admin_username
  administrator_login_password = var.admin_password
}

# Azure SQL Database
resource "azurerm_mssql_database" "db" {
  name                 = "AZ500LabDb"
  server_id            = azurerm_mssql_server.sql.id
  collation            = "SQL_Latin1_General_CP1_CI_AS"
  max_size_gb          = 2
  sku_name             = "Basic"
  sample_name          = "AdventureWorksLT"
  storage_account_type = "Geo"

}

resource "azurerm_mssql_database" "db_secondary" {
  name      = "AZ500LabDb-secondary"
  server_id = azurerm_mssql_server.sql_secondary.id

  create_mode = "Secondary"

  creation_source_database_id = azurerm_mssql_database.db.id

  sku_name = "Basic"
}

resource "azurerm_mssql_firewall_rule" "sql_allow_client_secondary" {
  name             = "AllowClientIP"
  server_id        = azurerm_mssql_server.sql_secondary.id
  start_ip_address = local.client_ip
  end_ip_address   = local.client_ip
}

resource "azurerm_mssql_firewall_rule" "sql_allow_client" {
  name             = "AllowClientIP"
  server_id        = azurerm_mssql_server.sql.id
  start_ip_address = local.client_ip
  end_ip_address   = local.client_ip
}
