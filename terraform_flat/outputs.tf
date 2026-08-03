# =============================================================================
# OUTPUTS — the contract this root offers downstream pipelines
# -----------------------------------------------------------------------------
# Three tiers, each with a different consumer in mind:
#
#   1. SCALARS    — plumbing. Names and IDs another Terraform root, an az CLI
#                   script, or a CMDB can consume.
#   2. SENSITIVE  — credentials and SAS URLs, marked so they never land in a log.
#   3. COMPOSITE  — ready-to-use artefacts: a rendered Ansible inventory, a
#                   --extra-vars JSON object, a deployment summary.
#
# The composite tier is what makes vm-config.sh able to drop `az` entirely. Every
# value that script used to look up with `az vm list-ip-addresses`,
# `az storage account keys list` and `az storage blob generate-sas` is emitted here
# instead, computed from state rather than re-queried from Azure.
#
# DELIBERATELY NOT COPIED from terraform/outputs.tf:433 — its
# infrastructure_json_export calls timestamp(), which makes that output change on
# every single plan. A permanently-diffing output trains reviewers to skim diffs,
# which is exactly when a real change slips through.
# =============================================================================

# -----------------------------------------------------------------------------
# Context
# -----------------------------------------------------------------------------

output "resource_group_name" {
  description = "Resource group holding the entire estate."
  value       = var.resource_group_name
}

output "location" {
  description = "Azure region the estate is deployed in."
  value       = var.location
}

output "subscription_id" {
  description = "Subscription ID, for scripts that must build ARM resource IDs by hand."
  value       = var.subscription_id
}

output "tenant_id" {
  description = "Entra tenant ID."
  value       = data.azurerm_client_config.current.tenant_id
}

output "resource_suffix" {
  description = "The suffix every resource name is derived from."
  value       = var.resource_suffix
}

output "client_ip" {
  description = "Public IP that was allowlisted in every NSG, firewall and network ACL at apply time."
  value       = local.client_ip
}

# -----------------------------------------------------------------------------
# Networking
# -----------------------------------------------------------------------------

output "vnet_id" {
  description = "Virtual network resource ID."
  value       = azurerm_virtual_network.main.id
}

output "vnet_name" {
  description = "Virtual network name."
  value       = azurerm_virtual_network.main.name
}

output "subnet_ids" {
  description = "Subnet IDs keyed by role. Both SQL node NICs live in 'main'; 'win' is created but unused (see network.tf)."
  value = merge(
    {
      main = azurerm_subnet.main.id
      win  = azurerm_subnet.win.id
    },
    var.create_bastion_subnet ? { bastion = azurerm_subnet.bastion[0].id } : {},
  )
}

output "windows_nsg_ids" {
  description = "Network security group IDs keyed by node."
  value       = { for k, v in azurerm_network_security_group.win : k => v.id }
}

output "windows_nic_ids" {
  description = "NIC IDs keyed by node. Needed to add both nodes to a load balancer backend pool when the AG listener is built."
  value       = { for k, v in azurerm_network_interface.win : k => v.id }
}

output "private_dns_zone_name" {
  description = "Private DNS zone providing WSFC and AG name resolution without Active Directory."
  value       = azurerm_private_dns_zone.corp.name
}

output "private_dns_records" {
  description = "Static A records seeded in the private zone, keyed by FQDN."
  value = {
    "aglistener.${var.private_dns_zone}" = var.ag_listener_ip
    "sqlcluster.${var.private_dns_zone}" = var.wsfc_cluster_ip
  }
}

# -----------------------------------------------------------------------------
# Windows SQL nodes
# -----------------------------------------------------------------------------

output "windows_vm_names" {
  description = "Windows SQL node names keyed by node."
  value       = { for k, v in azurerm_windows_virtual_machine.sql : k => v.name }
}

output "windows_vm_ids" {
  description = "Windows SQL node resource IDs keyed by node."
  value       = { for k, v in azurerm_windows_virtual_machine.sql : k => v.id }
}

output "windows_vm_public_ips" {
  description = "Public IPs of the Windows SQL nodes, keyed by node. Ansible connects to these over WinRM/HTTPS."
  value       = { for k, v in azurerm_public_ip.win : k => v.ip_address }
}

# -----------------------------------------------------------------------------
# Flat per-node scalars
# -----------------------------------------------------------------------------
# The maps above are the better shape for a pipeline that iterates nodes. These
# flat scalars exist because `terraform output -raw` CANNOT index into a map, and
# vm-config.sh reads one value per line with -raw so it stays readable without
# piping everything through jq.
#
# Names mirror env.conf's WIN_VM_NAME / WIN_VM_NAME_2 convention so the mapping
# from the original shell script is obvious.

output "windows_vm_name" {
  description = "SQL Node 1 (zone 1) VM name. Flat form of windows_vm_names[\"node1\"] for `terraform output -raw`."
  value       = azurerm_windows_virtual_machine.sql["node1"].name
}

output "windows_vm_name_2" {
  description = "SQL Node 2 (zone 2) VM name. Flat form of windows_vm_names[\"node2\"] for `terraform output -raw`."
  value       = azurerm_windows_virtual_machine.sql["node2"].name
}

output "windows_vm_public_ip" {
  description = "SQL Node 1 (zone 1) public IP. Flat form of windows_vm_public_ips[\"node1\"] for `terraform output -raw`."
  value       = azurerm_public_ip.win["node1"].ip_address
}

output "windows_vm_public_ip_2" {
  description = "SQL Node 2 (zone 2) public IP. Flat form of windows_vm_public_ips[\"node2\"] for `terraform output -raw`."
  value       = azurerm_public_ip.win["node2"].ip_address
}

output "windows_vm_private_ips" {
  description = "Private IPs of the Windows SQL nodes, keyed by node. These are the addresses WSFC and the AG use."
  value       = { for k, v in azurerm_network_interface.win : k => v.private_ip_address }
}

output "windows_vm_zones" {
  description = "Availability zone per node — the HA property the whole two-node design rests on."
  value       = { for k, v in local.win_nodes : k => v.zone }
}

output "windows_vm_principal_ids" {
  description = "System-assigned managed identity principal IDs, keyed by node."
  value       = { for k, v in azurerm_windows_virtual_machine.sql : k => v.identity[0].principal_id }
}

output "admin_username" {
  description = "Local administrator / SSH username on every VM."
  value       = var.admin_username
}

output "winrm_https_port" {
  description = "WinRM HTTPS listener port Ansible connects on."
  value       = var.winrm_https_port
}

output "ssh_private_key_path" {
  description = "Expanded path to the SSH private key, for the RHEL host's ansible_ssh_private_key_file."
  value       = pathexpand(var.ssh_private_key_path)
}

# -----------------------------------------------------------------------------
# Ansible playbook parameters
# -----------------------------------------------------------------------------
# Emitted so vm-config.sh can build its --extra-vars from Terraform rather than
# from env.conf. Trivial pass-throughs, but that is the point: it keeps a single
# source of truth for values the playbooks and the infrastructure must agree on.

output "sql_login" {
  description = "SQL login the Windows play creates (env.conf SQL_LOGIN)."
  value       = var.sql_login
}

output "win_sql_login" {
  description = "Local Windows account granted SQL access via Windows Authentication (env.conf WIN_SQL_LOGIN)."
  value       = var.win_sql_login
}

output "sql_installer_url" {
  description = "SQL Server 2022 Developer bootstrapper URL the Windows play downloads."
  value       = var.sql_installer_url
}

# -----------------------------------------------------------------------------
# Linux application VM (null when var.enable_linux_vm is false)
# -----------------------------------------------------------------------------

output "linux_vm_name" {
  description = "Linux application VM name, or null when the Linux track is disabled."
  value       = one(azurerm_linux_virtual_machine.app[*].name)
}

output "linux_vm_public_ip" {
  description = "Linux application VM public IP, or null when the Linux track is disabled."
  value       = one(azurerm_public_ip.linux[*].ip_address)
}

output "linux_vm_private_ip" {
  description = "Linux application VM private IP, or null when the Linux track is disabled."
  value       = one(azurerm_network_interface.linux[*].private_ip_address)
}

output "linux_vm_principal_id" {
  description = "Linux VM managed identity principal ID, or null when the Linux track is disabled."
  value       = try(azurerm_linux_virtual_machine.app[0].identity[0].principal_id, null)
}

# -----------------------------------------------------------------------------
# Disks and encryption sets
# -----------------------------------------------------------------------------

output "disk_encryption_set_ids" {
  description = "Disk Encryption Set IDs. Both wrap the same Key Vault key but are separate sets so the two workloads can be revoked independently."
  value = merge(
    { windows = azurerm_disk_encryption_set.win.id },
    var.enable_linux_vm ? { linux = azurerm_disk_encryption_set.linux[0].id } : {},
  )
}

output "windows_managed_disk_ids" {
  description = "Windows data disk IDs keyed by '<node>-<role>'."
  value       = { for k, v in azurerm_managed_disk.win : k => v.id }
}

output "windows_disk_layout" {
  description = "Disk role, size, LUN, caching and zone per disk — the map the in-guest formatting playbook needs to know which LUN becomes which drive letter."
  value = {
    for k, v in local.win_disks : k => {
      name    = v.name
      size_gb = v.size
      lun     = v.lun
      caching = v.caching
      zone    = v.zone
      node    = v.node
    }
  }
}

# -----------------------------------------------------------------------------
# Key Vault
# -----------------------------------------------------------------------------

output "key_vault_name" {
  description = "Key Vault name."
  value       = azurerm_key_vault.main.name
}

output "key_vault_id" {
  description = "Key Vault resource ID."
  value       = azurerm_key_vault.main.id
}

output "key_vault_uri" {
  description = "Key Vault data-plane URI, used by the Always Encrypted client driver and the .NET workload simulator."
  value       = azurerm_key_vault.main.vault_uri
}

output "key_vault_key_ids" {
  description = "Versioned key IDs for the three customer-managed keys. column_master_key is the one encrypted-cek.ps1 and the Always Encrypted DDL need."
  value = {
    column_master_key = azurerm_key_vault_key.column_master_key.id
    tde               = azurerm_key_vault_key.tde.id
    disk_encryption   = azurerm_key_vault_key.disk_encryption.id
  }
}

# -----------------------------------------------------------------------------
# Storage — re-exported from bootstrap/
# -----------------------------------------------------------------------------
# Every value below comes from data.terraform_remote_state.bootstrap, aliased to
# local.bootstrap in locals.tf. This root declares no storage resources; see
# data.tf for why the bridge exists and what it costs operationally.
#
# The output NAMES and shapes are unchanged from when storage.tf lived here.
# vm-config.sh reads these with `terraform output -raw <name>`, so renaming one is
# a breaking change even though the value now arrives from a different root.

output "storage_account_name" {
  description = "Storage account name."
  value       = local.bootstrap.storage_account_name
}

output "storage_account_id" {
  description = "Storage account resource ID."
  value       = local.bootstrap.storage_account_id
}

output "storage_primary_blob_endpoint" {
  description = "Blob service endpoint."
  value       = local.bootstrap.primary_blob_endpoint
}

output "storage_containers" {
  description = "Container names keyed by purpose."
  value = {
    backups = local.bootstrap.container_names["backups"]
    xevents = local.bootstrap.container_names["xevents"]
  }
}

# Reports what bootstrap actually uploaded, not what happens to be on this
# machine's disk. local.lab_archive_available would answer the second question —
# fileexists() here is true even when bootstrap never ran.
output "lab_archive_uploaded" {
  description = "Whether the DP-300 lab archive was present locally and uploaded. False on a checkout without docs/lab-files/."
  value       = local.bootstrap.lab_archive_uploaded
}

# -----------------------------------------------------------------------------
# Azure SQL (PHASE 5)
# -----------------------------------------------------------------------------

output "sql_server_name" {
  description = "Azure SQL logical server name, or null when PHASE 5 is disabled."
  value       = one(azurerm_mssql_server.main[*].name)
}

output "sql_server_fqdn" {
  description = "Azure SQL server FQDN — the connection target for sqlcmd, SSMS and the .NET workloads."
  value       = one(azurerm_mssql_server.main[*].fully_qualified_domain_name)
}

output "sql_server_id" {
  description = "Azure SQL server resource ID."
  value       = one(azurerm_mssql_server.main[*].id)
}

output "sql_server_principal_id" {
  description = "SQL server managed identity principal ID — the identity granted wrap/unwrap on the TDE key."
  value       = try(azurerm_mssql_server.main[0].identity[0].principal_id, null)
}

output "sql_database_name" {
  description = "Azure SQL database name."
  value       = one(azurerm_mssql_database.main[*].name)
}

output "sql_database_id" {
  description = "Azure SQL database resource ID. STEP 18's automatic-tuning REST call and STEP 20's initialisation both need this."
  value       = one(azurerm_mssql_database.main[*].id)
}

output "log_analytics_workspace_id" {
  description = "Log Analytics workspace resource ID receiving audit and diagnostic data."
  value       = one(azurerm_log_analytics_workspace.main[*].id)
}

output "log_analytics_workspace_customer_id" {
  description = "Log Analytics workspace GUID, for the Azure Monitor query API."
  value       = one(azurerm_log_analytics_workspace.main[*].workspace_id)
}

output "action_group_id" {
  description = "Action group ID the six SQL metric alerts notify."
  value       = one(azurerm_monitor_action_group.sql[*].id)
}

# -----------------------------------------------------------------------------
# SENSITIVE
# -----------------------------------------------------------------------------

output "admin_password" {
  description = "VM local admin and SQL administrator password. Consumed by vm-config.sh and passed to both Ansible plays."
  value       = var.admin_password
  sensitive   = true
}

output "lab_blob_sas_url" {
  description = <<-EOT
    Full HTTPS URL with SAS for the DP-300 lab archive. Replaces vm-config.sh's
    `az storage blob generate-sas`. The SAS window is pinned by time_rotating (see
    bootstrap/data.tf), so this value is stable between rotations instead of
    changing on every plan.

    Falls back to an EMPTY STRING, not null, when the archive was not uploaded:
    `terraform output -raw` errors on a null value, which under `set -euo pipefail`
    would kill vm-config.sh on any checkout without docs/lab-files/. An empty
    string lets the run continue and the playbook skip the download — the same
    outcome the original script had when SAS generation produced nothing.

    The empty-string fallback is applied by bootstrap's own output, so the try()
    that used to wrap this expression is gone rather than merely relocated.
  EOT
  value       = local.bootstrap.lab_blob_sas_url
  sensitive   = true
}

output "storage_primary_connection_string" {
  description = "Storage account connection string, for tooling that authenticates with the account key."
  value       = local.bootstrap.primary_connection_string
  sensitive   = true
}

output "sql_connection_string" {
  description = "ADO.NET connection string for the database, for the .NET workload simulator."
  value = try(
    "Server=tcp:${azurerm_mssql_server.main[0].fully_qualified_domain_name},1433;Initial Catalog=${azurerm_mssql_database.main[0].name};Persist Security Info=False;User ID=${var.admin_username};Password=${var.admin_password};MultipleActiveResultSets=False;Encrypt=True;TrustServerCertificate=False;Connection Timeout=30;",
    null,
  )
  sensitive = true
}

# -----------------------------------------------------------------------------
# COMPOSITE — ready-to-use artefacts
# -----------------------------------------------------------------------------

# The complete inventory.ini, rendered from state. vm-config.sh writes this
# straight to disk with `terraform output -raw ansible_inventory`.
#
# INI rather than the yamlencode() shape terraform/outputs.tf:391 uses, because
# the playbooks in this repo target `hosts: windows_vm` and `hosts: rhel_vm` — the
# modular root's output emits group names (linux_vms/windows_vms) that no playbook
# here actually consumes.
#
# Sensitive because it embeds ansible_password.
output "ansible_inventory" {
  description = "Complete Ansible inventory in INI format, ready to write to inventory.ini."
  value       = local.ansible_inventory
  sensitive   = true
}

# Every --extra-vars key both playbooks read, as one object.
#
# ansible-playbook --extra-vars accepts a JSON document, so vm-config.sh can pass
# `"$(terraform output -json ansible_vars)"` verbatim. That is quoting-safe by
# construction, unlike the space-separated "key=value key=value" string the current
# vm-config.sh builds, which breaks on any value containing a space.
output "ansible_vars" {
  description = "All --extra-vars for sql-server-on-rhel.yml and sql-server-on-windows.yml, as a single JSON-serialisable object."
  value = {
    # sql-server-on-rhel.yml
    vault_mssql_sa_password = var.admin_password
    # sql-server-on-windows.yml
    sa_password            = var.admin_password
    app_login              = var.sql_login
    app_login_password     = var.admin_password
    win_sql_login          = var.win_sql_login
    win_sql_login_password = var.admin_password
    sql_installer_url      = var.sql_installer_url
    # shared
    lab_blob_sas_url = local.bootstrap.lab_blob_sas_url
  }
  sensitive = true
}

output "infrastructure_summary" {
  description = "Nested summary of the deployed estate, for dashboards, CMDB ingestion or a deployment report."
  value = {
    context = {
      resource_group = var.resource_group_name
      location       = var.location
      suffix         = var.resource_suffix
    }
    network = {
      vnet          = azurerm_virtual_network.main.name
      address_space = var.vnet_address_space
      main_subnet   = azurerm_subnet.main.address_prefixes
      dns_zone      = azurerm_private_dns_zone.corp.name
      ag_listener   = var.ag_listener_ip
      wsfc_cluster  = var.wsfc_cluster_ip
    }
    windows_nodes = {
      for k, v in azurerm_windows_virtual_machine.sql : k => {
        name       = v.name
        size       = v.size
        zone       = v.zone
        public_ip  = azurerm_public_ip.win[k].ip_address
        private_ip = azurerm_network_interface.win[k].private_ip_address
        disk_count = length(local.win_disk_roles)
      }
    }
    linux_vm = var.enable_linux_vm ? {
      name      = azurerm_linux_virtual_machine.app[0].name
      size      = azurerm_linux_virtual_machine.app[0].size
      public_ip = azurerm_public_ip.linux[0].ip_address
    } : null
    encryption = {
      key_vault            = azurerm_key_vault.main.name
      purge_protection     = var.kv_purge_protection
      rbac_authorization   = false
      windows_des          = azurerm_disk_encryption_set.win.name
      linux_des            = var.enable_linux_vm ? azurerm_disk_encryption_set.linux[0].name : null
      customer_managed_key = azurerm_key_vault_key.disk_encryption.name
    }
    storage = {
      account        = local.bootstrap.storage_account_name
      default_action = var.storage_default_action
      containers     = [local.bootstrap.container_names["backups"], local.bootstrap.container_names["xevents"]]
      lab_archive    = local.bootstrap.lab_archive_uploaded
    }
    database = var.enable_phase5_sql ? {
      server_fqdn    = azurerm_mssql_server.main[0].fully_qualified_domain_name
      database       = azurerm_mssql_database.main[0].name
      sku            = var.sql_database_sku
      admin_user     = var.admin_username
      entra_admin    = var.entra_admin_login != "" ? var.entra_admin_login : null
      tde_cmk        = azurerm_key_vault_key.tde.name
      ltr_policy     = var.backup_ltr
      workspace      = azurerm_log_analytics_workspace.main[0].name
      alert_count    = length(local.sql_metric_alerts)
      retention_days = var.log_retention_days
    } : null
    known_gaps = {
      cli_shims_enabled = var.enable_cli_shims
      not_converted     = ["bastion.sh", "load-balancer.sh", "application-security-group.sh", "sql-engine-access.sh", "cluster-nsg-rules.sh", "identity.sh", "encrypted-cek.ps1"]
    }
  }
}

# Ready-to-paste operator commands. Cheap to produce and it removes the "how do I
# actually connect to this thing" step that otherwise costs a reader ten minutes.
output "connection_commands" {
  description = "Copy-paste commands for connecting to and verifying the deployed estate."
  value = {
    rdp_node1    = "open rdp://full%20address=s:${azurerm_public_ip.win["node1"].ip_address}:3389"
    rdp_node2    = "open rdp://full%20address=s:${azurerm_public_ip.win["node2"].ip_address}:3389"
    ssh_linux    = var.enable_linux_vm ? "ssh -i ${var.ssh_private_key_path} ${var.admin_username}@${azurerm_public_ip.linux[0].ip_address}" : null
    ansible_ping = "ansible -i inventory.ini windows_vm -m win_ping"
    sqlcmd = try(
      "sqlcmd -S ${azurerm_mssql_server.main[0].fully_qualified_domain_name} -d ${azurerm_mssql_database.main[0].name} -U ${var.admin_username} -G",
      null,
    )
    verify_disk_encryption  = "az disk list -g ${var.resource_group_name} --query \"[?diskEncryptionSetId!=null].{name:name,zone:zones[0],des:diskEncryptionSetId}\" -o table"
    verify_storage_firewall = "az storage account show -n ${local.bootstrap.storage_account_name} -g ${var.resource_group_name} --query networkRuleSet"
    verify_keys             = "az keyvault key list --vault-name ${azurerm_key_vault.main.name} -o table"
  }
}
