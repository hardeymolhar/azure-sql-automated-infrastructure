# ========================================
# Resource Group Outputs
# ========================================

output "primary_resource_group_id" {
  description = "ID of the primary resource group"
  value       = "/subscriptions/${var.subscription_id}/resourceGroups/${local.primary_rg}"
}

output "primary_resource_group_name" {
  description = "Name of the primary resource group"
  value       = local.primary_rg
}

output "secondary_resource_group_name" {
  description = "Name of the secondary resource group (if applicable)"
  value       = local.secondary_rg
}

# ========================================
# Linux Virtual Machine Outputs
# ========================================

output "linux_vm_id" {
  description = "ID of the Linux VM"
  value       = azurerm_linux_virtual_machine.vm[0].id
}

output "linux_vm_name" {
  description = "Name of the Linux VM"
  value       = azurerm_linux_virtual_machine.vm[0].name
}

output "linux_vm_private_ip" {
  description = "Private IP of the Linux VM"
  value       = azurerm_network_interface.nic.private_ip_address
}

output "linux_vm_public_ip" {
  description = "Public IP of the Linux VM"
  value       = azurerm_public_ip.vm_pip.ip_address
}

output "linux_vm_public_ip_id" {
  description = "ID of the Linux VM public IP"
  value       = azurerm_public_ip.vm_pip.id
}

output "linux_vm_fqdn" {
  description = "FQDN of the Linux VM (if applicable)"
  value       = azurerm_public_ip.vm_pip.fqdn
}

output "linux_vm_principal_id" {
  description = "Principal ID of Linux VM's managed identity"
  value       = azurerm_linux_virtual_machine.vm[0].identity[0].principal_id
}

output "linux_nic_id" {
  description = "ID of the Linux VM's network interface"
  value       = azurerm_network_interface.nic.id
}

# ========================================
# Database Virtual Machine Outputs
# ========================================

output "db_vm_ids" {
  description = "IDs of the Windows Database VMs"
  value       = azurerm_windows_virtual_machine.db_vm[*].id
}

output "db_vm_names" {
  description = "Names of the Windows Database VMs"
  value       = azurerm_windows_virtual_machine.db_vm[*].name
}

output "db_vm_private_ips" {
  description = "Private IPs of the Windows Database VMs"
  value       = azurerm_network_interface.db_nic.private_ip_address
}

output "db_vm_public_ip" {
  description = "Public IP of the Database VM"
  value       = azurerm_public_ip.db_vm_pip.ip_address
}

output "db_vm_public_ip_id" {
  description = "ID of the Database VM public IP"
  value       = azurerm_public_ip.db_vm_pip.id
}

output "db_vm_principal_ids" {
  description = "Principal IDs of Database VMs' managed identities"
  value       = azurerm_windows_virtual_machine.db_vm[*].identity[0].principal_id
}

output "db_nic_id" {
  description = "ID of the Database VM's network interface"
  value       = azurerm_network_interface.db_nic.id
}

# ========================================
# Networking Outputs
# ========================================

output "vnets" {
  description = "Virtual Network details"
  value = {
    for name, vnet in azurerm_virtual_network.vnet : name => {
      id            = vnet.id
      name          = vnet.name
      address_space = vnet.address_space
    }
  }
}

output "subnets" {
  description = "Subnet details by VNET and subnet name"
  value = {
    for key, subnet in azurerm_subnet.subnet : key => {
      id               = subnet.id
      name             = subnet.name
      address_prefixes = subnet.address_prefixes
      vnet_name        = subnet.virtual_network_name
    }
  }
}

output "network_security_groups" {
  description = "NSG details mapped by subnet"
  value = {
    for key, nsg in azurerm_network_security_group.nsg : key => {
      id   = nsg.id
      name = nsg.name
    }
  }
}

output "bastion_host_id" {
  description = "ID of the Bastion Host"
  value       = azurerm_bastion_host.bastion.id
}

output "bastion_host_name" {
  description = "Name of the Bastion Host"
  value       = azurerm_bastion_host.bastion.name
}

output "bastion_public_ip" {
  description = "Public IP of the Bastion Host"
  value       = azurerm_public_ip.bastion_pip.ip_address
}

output "bastion_public_ip_id" {
  description = "ID of the Bastion Host's public IP"
  value       = azurerm_public_ip.bastion_pip.id
}

# ========================================
# Database Managed Disks Outputs
# ========================================

output "data_disk_ids" {
  description = "IDs of all data disks"
  value       = azurerm_managed_disk.db_data_disk[*].id
}

output "data_disk_names" {
  description = "Names of all data disks"
  value       = azurerm_managed_disk.db_data_disk[*].name
}

output "log_disk_ids" {
  description = "IDs of all log disks"
  value       = azurerm_managed_disk.db_log_disk[*].id
}

output "log_disk_names" {
  description = "Names of all log disks"
  value       = azurerm_managed_disk.db_log_disk[*].name
}

output "disk_attachment_details" {
  description = "Data disk attachment mapping"
  value = {
    data_disk_lun_start = local.data_lun_start
    log_disk_lun_start  = local.log_lun_start
    data_disks_per_vm   = var.data_disks_per_vm
    log_disks_per_vm    = var.log_disks_per_vm
  }
}

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
  value       = var.admin_username
  sensitive   = false
}

# ========================================
# SQL Database Connection Strings
# ========================================

output "primary_sql_connection_string" {
  description = "JDBC connection string for primary SQL Database"
  value = [
    for db in azurerm_mssql_database.db :
  "jdbc:sqlserver://${azurerm_mssql_server.sql.fully_qualified_domain_name}:1433;database=${db.name};user=${var.admin_username}@${azurerm_mssql_server.sql.name};password=${var.admin_password};encrypt=true;trustServerCertificate=false;hostNameInCertificate=*.database.windows.net;loginTimeout=30;"]
  sensitive = true
}

output "primary_sql_connection_string_ado" {
  description = "ADO.NET connection string for primary SQL Database"
  value = [
    for db in azurerm_mssql_database.db :
    "Server=tcp:${azurerm_mssql_server.sql.fully_qualified_domain_name},1433;Initial Catalog=${db.name};Persist Security Info=False;User ID=${var.admin_username};Password=${var.admin_password};MultipleActiveResultSets=False;Encrypt=True;TrustServerCertificate=False;Connection Timeout=30;"
  ]
  sensitive = true
}


/*
output "secondary_sql_connection_string" {
  description = "JDBC connection string for secondary SQL Database (read-only replica)"
  value       = "jdbc:sqlserver://${azurerm_mssql_server.sql_secondary.fully_qualified_domain_name}:1433;database=${azurerm_mssql_database.db_secondary.name};user=${var.admin_username}@${azurerm_mssql_server.sql_secondary.name};password=${var.admin_password};encrypt=true;trustServerCertificate=false;hostNameInCertificate=*.database.windows.net;loginTimeout=30;"
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

# ========================================
# Connection Hints for Ansible/Deployment Scripts
# ========================================

output "ansible_inventory" {
  description = "Ansible inventory format for automation"
  value = yamlencode({
    all = {
      vars = {
        ansible_user   = var.admin_username
        ansible_become = true
      }
      children = {
        linux_vms = {
          hosts = {
            (azurerm_linux_virtual_machine.vm[0].name) = {
              ansible_host = azurerm_public_ip.vm_pip.ip_address
              private_ip   = azurerm_network_interface.nic.private_ip_address
            }
          }
        }
        windows_vms = {
          hosts = {
            for i, name in azurerm_windows_virtual_machine.db_vm[*].name :
            name => {
              ansible_host = azurerm_public_ip.db_vm_pip.ip_address
            }
          }
        }
        sql_servers = {
          hosts = {
            primary = {
              host = azurerm_mssql_server.sql.fully_qualified_domain_name
              port = 1433
            }
            secondary = {
              host = azurerm_mssql_server.sql_secondary.fully_qualified_domain_name
              port = 1433
            }
          }
        }
      }
    }
  })
}

output "infrastructure_json_export" {
  description = "Export infrastructure data as JSON for downstream automation tools"
  value = jsonencode({
    deployment = {
      timestamp       = timestamp()
      subscription_id = var.subscription_id
      regions         = [local.primary_location, local.secondary_location]
    }

    compute = {
      linux_vms = [
        {
          name        = azurerm_linux_virtual_machine.vm[0].name
          resource_id = azurerm_linux_virtual_machine.vm[0].id
          public_ip   = azurerm_public_ip.vm_pip.ip_address
          private_ip  = azurerm_network_interface.nic.private_ip_address
          ssh_command = "ssh ${var.admin_username}@${azurerm_public_ip.vm_pip.ip_address}"
        }
      ]

      windows_vms = [
        for i, vm in azurerm_windows_virtual_machine.db_vm : {
          name        = vm.name
          resource_id = vm.id
          public_ip   = azurerm_public_ip.db_vm_pip.ip_address
          rdp_command = "mstsc /v:${azurerm_public_ip.db_vm_pip.ip_address}"
        }
      ]
    }

    database = {
      primary = {
        server_name = azurerm_mssql_server.sql.name
        fqdn        = azurerm_mssql_server.sql.fully_qualified_domain_name
        database    = azurerm_mssql_database.db[*].name
        resource_id = azurerm_mssql_database.db[*].id
      }
      /*
      secondary = {
        server_name = azurerm_mssql_server.sql_secondary.name
        fqdn        = azurerm_mssql_server.sql_secondary.fully_qualified_domain_name
        database    = azurerm_mssql_database.db_secondary.name
        resource_id = azurerm_mssql_database.db_secondary.id
      }
      */
    }

    network = {
      vnets = [
        for name, vnet in azurerm_virtual_network.vnet : {
          name           = name
          resource_id    = vnet.id
          address_spaces = vnet.address_space
        }
      ]
    }
  })
}


output "terraform_identity" {
  value = {
    object_id = data.azurerm_client_config.current.object_id
    tenant_id = data.azurerm_client_config.current.tenant_id
  }
}


output "debug_nsg_rule_matrix" {
  value = local.nsg_rule_matrix
}
