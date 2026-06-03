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
  value       = module.vm.linux_vm_id
}

output "linux_vm_name" {
  description = "Name of the Linux VM"
  value       = module.vm.linux_vm_name
}

output "linux_vm_private_ip" {
  description = "Private IP of the Linux VM"
  value       = module.network.linux_nic_private_ip
}

output "linux_vm_public_ip" {
  description = "Public IP of the Linux VM"
  value       = module.network.linux_vm_public_ip
}

output "linux_vm_public_ip_id" {
  description = "ID of the Linux VM public IP"
  value       = module.network.linux_vm_public_ip_id
}

output "linux_vm_fqdn" {
  description = "FQDN of the Linux VM (if applicable)"
  value       = module.network.linux_vm_fqdn
}

output "linux_vm_principal_id" {
  description = "Principal ID of Linux VM's managed identity"
  value       = module.vm.linux_vm_principal_id
}

output "linux_nic_id" {
  description = "ID of the Linux VM's network interface"
  value       = module.network.linux_nic_id
}

# ========================================
# Database Virtual Machine Outputs
# ========================================

output "db_vm_ids" {
  description = "IDs of the Windows Database VMs"
  value       = module.vm.db_vm_ids
}

output "db_vm_names" {
  description = "Names of the Windows Database VMs"
  value       = module.vm.db_vm_names
}

output "db_vm_private_ips" {
  description = "Private IPs of the Windows Database VMs"
  value       = module.network.db_nic_private_ip
}

output "db_vm_public_ip" {
  description = "Public IP of the Database VM"
  value       = module.network.db_vm_public_ip
}

output "db_vm_public_ip_id" {
  description = "ID of the Database VM public IP"
  value       = module.network.db_vm_public_ip_id
}

output "db_vm_principal_ids" {
  description = "Principal IDs of Database VMs' managed identities"
  value       = module.vm.db_vm_principal_ids
}

output "db_nic_id" {
  description = "ID of the Database VM's network interface"
  value       = module.network.db_nic_id
}

# ========================================
# Networking Outputs
# ========================================

output "vnets" {
  description = "Virtual Network details"
  value       = module.network.vnets
}

output "subnets" {
  description = "Subnet details by VNET and subnet name"
  value       = module.network.subnets
}

output "network_security_groups" {
  description = "NSG details mapped by subnet"
  value       = module.network.network_security_groups
}

output "bastion_host_id" {
  description = "ID of the Bastion Host"
  value       = module.network.bastion_host_id
}

output "bastion_host_name" {
  description = "Name of the Bastion Host"
  value       = module.network.bastion_host_name
}

output "bastion_public_ip" {
  description = "Public IP of the Bastion Host"
  value       = module.network.bastion_public_ip
}

output "bastion_public_ip_id" {
  description = "ID of the Bastion Host's public IP"
  value       = module.network.bastion_public_ip_id
}

# ========================================
# Database Managed Disks Outputs
# ========================================

output "data_disk_ids" {
  description = "IDs of all data disks"
  value       = module.vm.data_disk_ids
}

output "data_disk_names" {
  description = "Names of all data disks"
  value       = module.vm.data_disk_names
}

output "log_disk_ids" {
  description = "IDs of all log disks"
  value       = module.vm.log_disk_ids
}

output "log_disk_names" {
  description = "Names of all log disks"
  value       = module.vm.log_disk_names
}

output "disk_attachment_details" {
  description = "Data disk attachment mapping"
  value       = module.vm.disk_attachment_details
}

# ========================================
# SQL Server Outputs
# ========================================

output "primary_sql_server_id" {
  description = "ID of the primary SQL Server"
  value       = module.sql.primary_sql_server_id
}

output "primary_sql_server_name" {
  description = "Name of the primary SQL Server"
  value       = module.sql.primary_sql_server_name
}

output "primary_sql_server_fqdn" {
  description = "Fully qualified domain name of the primary SQL Server"
  value       = module.sql.primary_sql_server_fqdn
}

output "secondary_sql_server_id" {
  description = "ID of the secondary SQL Server (for geo-replication)"
  value       = module.sql.secondary_sql_server_id
}

output "secondary_sql_server_name" {
  description = "Name of the secondary SQL Server"
  value       = module.sql.secondary_sql_server_name
}

output "secondary_sql_server_fqdn" {
  description = "Fully qualified domain name of the secondary SQL Server"
  value       = module.sql.secondary_sql_server_fqdn
}

output "primary_database_id" {
  description = "ID of the primary SQL Database"
  value       = module.sql.primary_database_id
}

output "primary_database_name" {
  description = "Name of the primary SQL Database"
  value       = module.sql.primary_database_name
}

output "sql_admin_username" {
  description = "SQL Server administrator username"
  value       = module.sql.sql_admin_username
  sensitive   = false
}

# ========================================
# SQL Database Connection Strings
# ========================================

output "primary_sql_connection_string" {
  description = "JDBC connection string for primary SQL Database"
  value       = module.sql.primary_sql_connection_string
  sensitive   = true
}

output "primary_sql_connection_string_ado" {
  description = "ADO.NET connection string for primary SQL Database"
  value       = module.sql.primary_sql_connection_string_ado
  sensitive   = true
}

output "sql_firewall_rules" {
  description = "SQL Server firewall rule details"
  value       = module.sql.sql_firewall_rules
}

# ========================================
# Monitoring & Logging Outputs
# ========================================

output "log_analytics_workspace_id" {
  description = "ID of the Log Analytics Workspace"
  value       = module.monitoring.log_analytics_workspace_id
}

output "log_analytics_workspace_name" {
  description = "Name of the Log Analytics Workspace"
  value       = module.monitoring.log_analytics_workspace_name
}

output "log_analytics_workspace_resource_id" {
  description = "Resource ID of the Log Analytics Workspace"
  value       = module.monitoring.log_analytics_workspace_resource_id
}

output "log_analytics_primary_key" {
  description = "Primary shared key for the Log Analytics Workspace"
  value       = module.monitoring.log_analytics_primary_key
  sensitive   = true
}

output "log_analytics_secondary_key" {
  description = "Secondary shared key for the Log Analytics Workspace"
  value       = module.monitoring.log_analytics_secondary_key
  sensitive   = true
}

# ========================================
# Security (Key Vault) Outputs
# ========================================

output "key_vault_id" {
  description = "ID of the Key Vault"
  value       = module.security.key_vault_id
}

output "key_vault_name" {
  description = "Name of the Key Vault"
  value       = module.security.key_vault_name
}

output "key_vault_uri" {
  description = "URI of the Key Vault"
  value       = module.security.key_vault_uri
}

# ========================================
# Private Endpoint Outputs
# ========================================

output "sql_private_endpoint_id" {
  description = "ID of the Azure SQL private endpoint"
  value       = module.private_endpoints.sql_private_endpoint_id
}

output "key_vault_private_endpoint_id" {
  description = "ID of the Key Vault private endpoint"
  value       = module.private_endpoints.key_vault_private_endpoint_id
}

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

output "terraform_identity" {
  value = {
    object_id = data.azurerm_client_config.current.object_id
    tenant_id = data.azurerm_client_config.current.tenant_id
  }
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
      name       = module.vm.linux_vm_name
      id         = module.vm.linux_vm_id
      public_ip  = module.network.linux_vm_public_ip
      private_ip = module.network.linux_nic_private_ip
      location   = local.primary_location
    }

    db_vms = {
      count              = var.vm_count
      names              = module.vm.db_vm_names
      ids                = module.vm.db_vm_ids
      availability_zones = module.vm.db_vm_zones
      public_ip          = module.network.db_vm_public_ip
    }

    database = {
      primary_server_fqdn   = module.sql.primary_sql_server_fqdn
      secondary_server_fqdn = module.sql.secondary_sql_server_fqdn
      primary_db_name       = module.sql.primary_database_name
      admin_user            = var.sqladmin_username
    }

    networking = {
      vnets             = keys(module.network.vnets)
      bastion_host_name = module.network.bastion_host_name
      bastion_public_ip = module.network.bastion_public_ip
    }

    storage = {
      total_data_disks  = module.vm.data_disk_count
      total_log_disks   = module.vm.log_disk_count
      data_disk_size_gb = 1024
      log_disk_size_gb  = 512
    }

    monitoring = {
      log_analytics_workspace_id = module.monitoring.log_analytics_workspace_id
      retention_days             = module.monitoring.log_analytics_retention_days
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
            (module.vm.linux_vm_name) = {
              ansible_host = module.network.linux_vm_public_ip
              private_ip   = module.network.linux_nic_private_ip
            }
          }
        }
        windows_vms = {
          hosts = {
            for name in module.vm.db_vm_names :
            name => {
              ansible_host = module.network.db_vm_public_ip
            }
          }
        }
        sql_servers = {
          hosts = {
            primary = {
              host = module.sql.primary_sql_server_fqdn
              port = 1433
            }
            secondary = {
              host = module.sql.secondary_sql_server_fqdn
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
          name        = module.vm.linux_vm_name
          resource_id = module.vm.linux_vm_id
          public_ip   = module.network.linux_vm_public_ip
          private_ip  = module.network.linux_nic_private_ip
          ssh_command = "ssh ${var.admin_username}@${module.network.linux_vm_public_ip}"
        }
      ]

      windows_vms = [
        for i, name in module.vm.db_vm_names : {
          name        = name
          resource_id = module.vm.db_vm_ids[i]
          public_ip   = module.network.db_vm_public_ip
          rdp_command = "mstsc /v:${module.network.db_vm_public_ip}"
        }
      ]
    }

    database = {
      primary = {
        server_name = module.sql.primary_sql_server_name
        fqdn        = module.sql.primary_sql_server_fqdn
        database    = module.sql.primary_database_name
        resource_id = module.sql.primary_database_id
      }
    }

    network = {
      vnets = [
        for name, vnet in module.network.vnets : {
          name           = name
          resource_id    = vnet.id
          address_spaces = vnet.address_space
        }
      ]
    }
  })
}
