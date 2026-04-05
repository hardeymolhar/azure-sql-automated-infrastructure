resource "azurerm_mssql_database" "db_secondary" {

  count     = 10
  name      = "AZ500LabDb-secondary-${count.index}"
  server_id = azurerm_mssql_server.sql_secondary.id

  create_mode = "Secondary"

  creation_source_database_id = azurerm_mssql_database.db[count.index].id

  sku_name = "Basic"
}
