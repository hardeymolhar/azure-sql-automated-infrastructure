

resource "random_string" "suffix" {
  length  = 4
  upper   = false
  special = false
}


# Azure SQL Server
############################################
# PRIMARY AZURE SQL LOGICAL SERVER
############################################
# Hosts the primary (read-write) database.
# This is the source of truth before failover.
resource "azurerm_mssql_server" "sql" {
  name                = "sql-automated-server-${random_string.suffix.result}"
  resource_group_name = local.primary_rg
  location            = local.primary_location
  version             = "12.0"

  # Admin credentials must match secondary server
  # for failover group pairing to succeed.
  administrator_login          = var.admin_username
  administrator_login_password = var.admin_password

  minimum_tls_version = "1.2"

  identity {
    type = "SystemAssigned"
  }

  connection_policy = "Proxy"

}




############################################
# SECONDARY AZURE SQL LOGICAL SERVER
############################################
# Hosts geo-secondary databases during replication.
# Must be in a DIFFERENT region for DR.
resource "azurerm_mssql_server" "sql_secondary" {

  name                = "whizlabserver-replica-${random_string.suffix.result}"
  resource_group_name = local.primary_rg
  location            = local.secondary_location
  version             = "12.0"

  # MUST match primary server credentials

  administrator_login          = var.admin_username
  administrator_login_password = var.admin_password
  minimum_tls_version          = "1.2"

  identity {
    type = "SystemAssigned"
  }

  connection_policy = "Proxy"
}


############################################
# PRIMARY DATABASE
############################################
# This is the only database explicitly defined.
# Secondary DB will be automatically created
# and managed by the failover group.
# Azure SQL Database
resource "azurerm_mssql_database" "db" {

  count                = 20
  name                 = "AZ500LabDb-${count.index}"
  server_id            = azurerm_mssql_server.sql.id
  collation            = "SQL_Latin1_General_CP1_CI_AS"
  max_size_gb          = 2
  sku_name             = "Basic"
  sample_name          = "AdventureWorksLT"
  storage_account_type = "Geo"


}

############################################
# SQL AUDITING - SERVER LEVEL
############################################
# Enables Azure SQL Auditing on both logical servers.
# Audit events are sent to Azure Monitor and collected by
# the diagnostic settings below.
resource "azurerm_mssql_server_extended_auditing_policy" "sql_audit" {
  server_id              = azurerm_mssql_server.sql.id
  log_monitoring_enabled = true
  retention_in_days      = 30
}

resource "azurerm_mssql_server_extended_auditing_policy" "sql_secondary_audit" {
  server_id              = azurerm_mssql_server.sql_secondary.id
  log_monitoring_enabled = true
  retention_in_days      = 30
}

resource "azurerm_monitor_diagnostic_setting" "sql_server_audit_logs" {
  name                       = "sql-server-audit-logs"
  target_resource_id         = "${azurerm_mssql_server.sql.id}/databases/master"
  log_analytics_workspace_id = azurerm_log_analytics_workspace.law.id

  enabled_log {
    category = "SQLSecurityAuditEvents"
  }

  metric {
    category = "AllMetrics"
    enabled  = true
  }

  depends_on = [azurerm_mssql_server_extended_auditing_policy.sql_audit]
}

resource "azurerm_monitor_diagnostic_setting" "sql_secondary_server_audit_logs" {
  name                       = "sql-secondary-server-audit-logs"
  target_resource_id         = "${azurerm_mssql_server.sql_secondary.id}/databases/master"
  log_analytics_workspace_id = azurerm_log_analytics_workspace.law.id

  enabled_log {
    category = "SQLSecurityAuditEvents"
  }

  metric {
    category = "AllMetrics"
    enabled  = true
  }

  depends_on = [azurerm_mssql_server_extended_auditing_policy.sql_secondary_audit]
}

############################################
# SQL AUDITING - DATABASE LEVEL
############################################
# Enables Azure SQL Auditing on each Terraform-managed database.
resource "azurerm_mssql_database_extended_auditing_policy" "sql_db_audit" {
  for_each = {
    for idx, db in azurerm_mssql_database.db :
    idx => db.id
  }

  database_id            = each.value
  log_monitoring_enabled = true
  retention_in_days      = 30
}

resource "azurerm_mssql_database_extended_auditing_policy" "sql_db_secondary_audit" {
  for_each = {
    for idx, db in azurerm_mssql_database.db_secondary :
    idx => db.id
  }

  database_id            = each.value
  log_monitoring_enabled = true
  retention_in_days      = 30
}

resource "azurerm_monitor_diagnostic_setting" "sql_db_secondary_audit_logs" {
  for_each = {
    for idx, db in azurerm_mssql_database.db_secondary :
    idx => db.id
  }

  name                       = "sql-db-secondary-audit-${each.key}"
  target_resource_id         = each.value
  log_analytics_workspace_id = azurerm_log_analytics_workspace.law.id

  enabled_log {
    category = "SQLSecurityAuditEvents"
  }

  metric {
    category = "AllMetrics"
    enabled  = true
  }

  depends_on = [azurerm_mssql_database_extended_auditing_policy.sql_db_secondary_audit]
}


############################################
# FAILOVER GROUP
############################################
# Provides:
# - Automatic geo-replication
# - Failover orchestration
# - Stable DNS endpoints (critical for apps)
#
# DO NOT combine with manual secondary DB creation.
resource "azurerm_mssql_failover_group" "fog" {
  name      = "sql-failover-group-2345544"
  server_id = azurerm_mssql_server.sql.id

  # List of databases to include in replication
  # Failover group will create and manage secondaries
  databases = slice(azurerm_mssql_database.db[*].id, 10, 20)

  ##########################################
  # SECONDARY SERVER PAIRING
  ##########################################
  partner_server {
    id = azurerm_mssql_server.sql_secondary.id
  }

  ##########################################
  # FAILOVER POLICY (READ-WRITE ENDPOINT)
  ##########################################
  # Controls automatic failover behavior
  read_write_endpoint_failover_policy {
    mode = "Automatic"

    # Grace period before failover triggers
    # Helps avoid failover during transient issues
    grace_minutes = 60
  }

  depends_on = [azurerm_mssql_database.db]
}

############################################
# FIREWALL RULE - PRIMARY SERVER
############################################
# Allows client access to primary region
resource "azurerm_mssql_firewall_rule" "sql_allow_client" {
  name             = "AllowClientIP"
  server_id        = azurerm_mssql_server.sql.id
  start_ip_address = local.client_ip
  end_ip_address   = local.client_ip
}

############################################
# FIREWALL RULE - SECONDARY SERVER
############################################
# Required for failover scenarios.
# Without this, failover succeeds but connectivity fails.
resource "azurerm_mssql_firewall_rule" "sql_allow_client_secondary" {
  name             = "AllowClientIP"
  server_id        = azurerm_mssql_server.sql_secondary.id
  start_ip_address = local.client_ip
  end_ip_address   = local.client_ip
}

