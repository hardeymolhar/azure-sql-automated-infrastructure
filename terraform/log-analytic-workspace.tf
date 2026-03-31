resource "azurerm_log_analytics_workspace" "law" {
  name                = "cosmos-law"
  location            = local.primary_location
  resource_group_name = local.primary_rg

  sku               = "PerGB2018"
  retention_in_days = 30
}


resource "azurerm_monitor_diagnostic_setting" "sql_db_logs" {
  name                       = "sql-db-diagnostics"
  target_resource_id         = azurerm_mssql_database.db.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.law.id

  enabled_log {
    category_group = "allLogs"
  }

  metric {
    category = "AllMetrics"
    enabled  = true
  }
}

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
