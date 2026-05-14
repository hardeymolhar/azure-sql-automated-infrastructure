resource "azurerm_log_analytics_workspace" "law" {
  name                = "cosmos-law"
  location            = var.primary_location
  resource_group_name = var.primary_rg

  sku               = "PerGB2018"
  retention_in_days = 30
}


resource "azurerm_monitor_diagnostic_setting" "sql_db_logs" {

  for_each = {
    for idx, db in azurerm_mssql_database.db :
    idx => db.id
  }

  name                       = "sql-db-diag-${each.key}"
  target_resource_id         = each.value
  log_analytics_workspace_id = azurerm_log_analytics_workspace.law.id

  enabled_log {
    category_group = "allLogs"
  }

  metric {
    category = "AllMetrics"
    enabled  = true
  }
}



/*
resource "azurerm_monitor_diagnostic_setting" "sql_db_secondary_logs" {
  name                       = "sql-db-secondary-diagnostics"
  target_resource_id         = azurerm_mssql_database.db_secondary.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.law.id

  enabled_log {
    category_group = "allLogs"
  }

  metric {
    category = "AllMetrics"
    enabled  = true
  }
}
*/