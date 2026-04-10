

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


