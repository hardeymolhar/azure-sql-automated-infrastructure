
# ========================================
# SQL Server Outputs
# ========================================

output "primary_sql_server_id" {
  description = "ID of the primary SQL Server"
  value       = azurerm_mssql_server.sql.id
}

output "primary_sql_server_name" {
  description = "Name of the primary SQL Server"
  value       = azurerm_mssql_server.sql.name
}

output "primary_sql_server_fqdn" {
  description = "Fully qualified domain name of the primary SQL Server"
  value       = azurerm_mssql_server.sql.fully_qualified_domain_name
}

output "secondary_sql_server_id" {
  description = "ID of the secondary SQL Server (for geo-replication)"
  value       = azurerm_mssql_server.sql_secondary.id
}

output "secondary_sql_server_name" {
  description = "Name of the secondary SQL Server"
  value       = azurerm_mssql_server.sql_secondary.name
}

output "secondary_sql_server_fqdn" {
  description = "Fully qualified domain name of the secondary SQL Server"
  value       = azurerm_mssql_server.sql_secondary.fully_qualified_domain_name
}

output "primary_database_id" {
  description = "ID of the primary SQL Database"
  value       = azurerm_mssql_database.db[*].id
}

output "primary_database_name" {
  description = "Name of the primary SQL Database"
  value       = azurerm_mssql_database.db[*].name
}

/*
output "secondary_database_id" {
  description = "ID of the secondary SQL Database (replica)"
  value       = azurerm_mssql_database.db_secondary.id
}


output "secondary_database_name" {
  description = "Name of the secondary SQL Database"
  value       = azurerm_mssql_database.db_secondary.name
}
*/
output "sql_admin_username" {
  description = "SQL Server administrator username"
  value       = var.sqladmin_username
  sensitive   = false
}

# ========================================
# SQL Database Connection Strings
# ========================================

output "primary_sql_connection_string" {
  description = "JDBC connection string for primary SQL Database"
  value = [
    for db in azurerm_mssql_database.db :
  "jdbc:sqlserver://${azurerm_mssql_server.sql.fully_qualified_domain_name}:1433;database=${db.name};user=${var.sqladmin_username}@${azurerm_mssql_server.sql.name};password=${var.sqladmin_password};encrypt=true;trustServerCertificate=false;hostNameInCertificate=*.database.windows.net;loginTimeout=30;"]
  sensitive = true
}

output "primary_sql_connection_string_ado" {
  description = "ADO.NET connection string for primary SQL Database"
  value = [
    for db in azurerm_mssql_database.db :
    "Server=tcp:${azurerm_mssql_server.sql.fully_qualified_domain_name},1433;Initial Catalog=${db.name};Persist Security Info=False;User ID=${var.sqladmin_username};Password=${var.sqladmin_password};MultipleActiveResultSets=False;Encrypt=True;TrustServerCertificate=False;Connection Timeout=30;"
  ]
  sensitive = true
}


/*
output "secondary_sql_connection_string" {
  description = "JDBC connection string for secondary SQL Database (read-only replica)"
  value       = "jdbc:sqlserver://${azurerm_mssql_server.sql_secondary.fully_qualified_domain_name}:1433;database=${azurerm_mssql_database.db_secondary.name};user=${var.sqladmin_username}@${azurerm_mssql_server.sql_secondary.name};password=${var.sqladmin_password};encrypt=true;trustServerCertificate=false;hostNameInCertificate=*.database.windows.net;loginTimeout=30;"
  sensitive   = true
}
*/

output "sql_firewall_rules" {
  description = "SQL Server firewall rule details"
  value = {
    primary_firewall_client_ip   = azurerm_mssql_firewall_rule.sql_allow_client.start_ip_address
    secondary_firewall_client_ip = azurerm_mssql_firewall_rule.sql_allow_client_secondary.start_ip_address
  }
}
