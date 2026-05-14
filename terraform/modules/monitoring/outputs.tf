
# ========================================
# Monitoring & Logging Outputs
# ========================================

output "log_analytics_workspace_id" {
  description = "ID of the Log Analytics Workspace"
  value       = azurerm_log_analytics_workspace.law.id
}



output "log_analytics_workspace_name" {
  description = "Name of the Log Analytics Workspace"
  value       = azurerm_log_analytics_workspace.law.name
}

output "log_analytics_workspace_resource_id" {
  description = "Resource ID of the Log Analytics Workspace"
  value       = azurerm_log_analytics_workspace.law.workspace_id
}

output "log_analytics_primary_key" {
  description = "Primary shared key for the Log Analytics Workspace"
  value       = azurerm_log_analytics_workspace.law.primary_shared_key
  sensitive   = true
}

output "log_analytics_secondary_key" {
  description = "Secondary shared key for the Log Analytics Workspace"
  value       = azurerm_log_analytics_workspace.law.secondary_shared_key
  sensitive   = true
}


/*
output "diagnostic_settings" {
  description = "Diagnostic settings configured for SQL databases"
  value = {
    primary_database   = azurerm_monitor_diagnostic_setting.sql_db_logs.id
    secondary_database = azurerm_monitor_diagnostic_setting.sql_db_secondary_logs.id
  }
}

*/

# ========================================
# Authentication & Security Outputs
# ========================================

output "client_ip_address" {
  description = "Current client IP address (used for firewall rules)"
  value       = local.client_ip
}

output "subscription_id" {
  description = "Azure Subscription ID"
  value       = var.subscription_id
}

output "tenant_id" {
  description = "Azure Tenant ID"
  value       = data.azurerm_client_config.current.tenant_id
}

# ========================================
# Infrastructure Summary for Automation
# ========================================

output "infrastructure_summary" {
  description = "Comprehensive infrastructure summary for automation and scripts"
  value = {
    primary_location   = local.primary_location
    secondary_location = local.secondary_location
    primary_rg         = local.primary_rg
    secondary_rg       = local.secondary_rg

    linux_vm = {
      name       = azurerm_linux_virtual_machine.vm[0].name
      id         = azurerm_linux_virtual_machine.vm[0].id
      public_ip  = azurerm_public_ip.vm_pip.ip_address
      private_ip = azurerm_network_interface.nic.private_ip_address
      location   = local.primary_location
    }

    db_vms = {
      count              = var.vm_count
      names              = azurerm_windows_virtual_machine.db_vm[*].name
      ids                = azurerm_windows_virtual_machine.db_vm[*].id
      availability_zones = azurerm_windows_virtual_machine.db_vm[*].zone
      public_ip          = azurerm_public_ip.db_vm_pip.ip_address
    }

    database = {
      primary_server_fqdn   = azurerm_mssql_server.sql.fully_qualified_domain_name
      secondary_server_fqdn = azurerm_mssql_server.sql_secondary.fully_qualified_domain_name
      primary_db_name       = azurerm_mssql_database.db[*].name
      admin_user            = var.admin_username
    }

    networking = {
      vnets             = [for name in keys(azurerm_virtual_network.vnet) : name]
      bastion_host_name = azurerm_bastion_host.bastion.name
      bastion_public_ip = azurerm_public_ip.bastion_pip.ip_address
    }

    storage = {
      total_data_disks  = length(azurerm_managed_disk.db_data_disk)
      total_log_disks   = length(azurerm_managed_disk.db_log_disk)
      data_disk_size_gb = 1024
      log_disk_size_gb  = 512
    }

    monitoring = {
      log_analytics_workspace_id = azurerm_log_analytics_workspace.law.id
      retention_days             = azurerm_log_analytics_workspace.law.retention_in_days
    }
  }
}