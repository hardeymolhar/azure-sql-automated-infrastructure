# =============================================================================
# INPUT VARIABLES
# -----------------------------------------------------------------------------
# Every value here has a direct ancestor in scripts/shell/test-env/env.conf. Where
# env.conf resolved a value by running a command at source time (az group list
# "[1].name", az ad signed-in-user show, curl ipify), that is called out — those
# are the places the imperative pipeline was least reproducible and where a
# declared input is the actual improvement.
#
# Naming: env.conf's RESOURCE_SUFFIX is the single knob that renames the estate.
# It stays a single knob here (var.resource_suffix) and every derived name is
# computed in locals.tf, which retires var-config.sh's perl-in-place rewriting.
# =============================================================================

# -----------------------------------------------------------------------------
# Azure context
# -----------------------------------------------------------------------------

variable "subscription_id" {
  description = "Azure subscription ID the estate is deployed into (env.conf SUBSCRIPTION_ID)."
  type        = string
}

variable "resource_group_name" {
  description = <<-EOT
    Pre-existing resource group. No azurerm_resource_group is created by this root
    — the Whizlabs sandbox hands out RGs and the signed-in principal cannot create
    them. This replaces env.conf's `az group list --query "[1].name"`, which was an
    index into whatever the sandbox happened to return.
  EOT
  type        = string
}

variable "location" {
  description = <<-EOT
    Single Azure region for the whole estate (env.conf LOCATION). Deliberately a
    string, not the list(string) the modular root uses: terraform/ is multi-region
    because failover groups need a secondary, whereas this root is single-region by
    construction. See README.md for the full rationale.
  EOT
  type        = string
  default     = "centralindia"
}

variable "resource_suffix" {
  description = "Shared name suffix for every resource (env.conf RESOURCE_SUFFIX)."
  type        = string
  default     = "stg-ind-49"

  validation {
    condition     = can(regex("^[a-z0-9-]{1,20}$", var.resource_suffix))
    error_message = "resource_suffix must be 1-20 lowercase alphanumeric or hyphen characters."
  }
}

variable "tags" {
  description = "Tags applied to every resource that supports them."
  type        = map(string)
  default = {
    project     = "azure-sql-automated-infrastructure"
    track       = "iaas"
    managed_by  = "terraform"
    terraform   = "terraform_flat"
    environment = "sandbox"
  }
}

# -----------------------------------------------------------------------------
# Feature gates
# -----------------------------------------------------------------------------

variable "enable_linux_vm" {
  description = <<-EOT
    Create the Linux (RHEL) application VM, its dedicated Disk Encryption Set and
    its four managed disks — the Terraform equivalent of encrypted-mgd-disks.sh and
    app-vm.sh. Defaults to false because both of those are commented out in
    db-deploy.sh (STEPs 5 and 6); app-vm.sh also cannot run as written, since
    app-vm.sh:28 calls an undefined `resource_exists` function.
  EOT
  type        = bool
  default     = true
}

variable "enable_phase5_sql" {
  description = <<-EOT
    Create the PaaS Azure SQL estate — db-deploy.sh PHASE 5, STEPs 13-19. Defaults
    to true so the flat root reproduces the full documented pipeline; set false to
    deploy only the IaaS substrate.
  EOT
  type        = bool
  default     = true
}

variable "enable_cli_shims" {
  description = <<-EOT
    Run the two `az` CLI shims for behaviour that has no azurerm resource in 4.75.0:
    the XEvent container stored access policy, and SQL automatic tuning (STEP 18).
    These execute via local-exec, so they need the az CLI on PATH and an active
    `az login`. Set false for plan-only or CI runs.
  EOT
  type        = bool
  default     = true
}

# -----------------------------------------------------------------------------
# Credentials — all sensitive, all supplied via the gitignored terraform.tfvars
# -----------------------------------------------------------------------------

variable "admin_username" {
  description = "Local administrator / SSH user on every VM (env.conf ADMIN_USERNAME)."
  type        = string
  default     = "sqladmin"
}

variable "admin_password" {
  description = "Windows local admin password and Azure SQL administrator password (env.conf ADMIN_PASSWORD)."
  type        = string
  sensitive   = true
}

variable "sql_login" {
  description = "SQL login created in-guest by the Ansible play (env.conf SQL_LOGIN)."
  type        = string
  default     = "appuser"
}

variable "win_sql_login" {
  description = "Local Windows account granted SQL access via Windows Authentication (env.conf WIN_SQL_LOGIN)."
  type        = string
  default     = "winsqluser"
}

variable "ssh_private_key_path" {
  description = "Path to the SSH private key stored as a Key Vault secret (env.conf SSH_PRIVATE_KEY_PATH)."
  type        = string
  default     = "~/.ssh/ssh_key/vm-key/vm-key"
}

variable "ssh_public_key_path" {
  description = "Path to the SSH public key used by the Linux VM and stored in Key Vault (env.conf SSH_PUBLIC_KEY_PATH)."
  type        = string
  default     = "~/.ssh/ssh_key/vm-key/vm-key.pub"
}

# -----------------------------------------------------------------------------
# Networking (network.sh)
# -----------------------------------------------------------------------------

variable "vnet_address_space" {
  description = "VNet address space (env.conf VNET_ADDRESS_PREFIX)."
  type        = list(string)
  default     = ["10.10.0.0/16"]
}

variable "main_subnet_prefix" {
  description = "Workload subnet holding BOTH Windows NICs and the Linux NIC (network.sh:29-36)."
  type        = list(string)
  default     = ["10.10.1.0/24"]
}

variable "win_subnet_prefix" {
  description = <<-EOT
    Secondary Windows subnet (env.conf WIN_SUBNET_PREFIX). network.sh creates it and
    gives it a Microsoft.Storage service endpoint, but no NIC is ever placed in it —
    both SQL nodes share the main subnet so the Always On AG stays single-subnet.
    Preserved here for parity and because storage.sh registers a VNet rule for it.
  EOT
  type        = list(string)
  default     = ["10.10.2.0/24"]
}

variable "bastion_subnet_prefix" {
  description = "AzureBastionSubnet prefix, reserved for a future bastion.sh conversion (env.conf BASTION_SUBNET_PREFIX)."
  type        = list(string)
  default     = ["10.10.3.0/26"]
}

variable "create_bastion_subnet" {
  description = "Reserve the AzureBastionSubnet range. The bastion host itself is not in scope for this root."
  type        = bool
  default     = false
}

# -----------------------------------------------------------------------------
# Private DNS (private-dns.sh)
# -----------------------------------------------------------------------------

variable "private_dns_zone" {
  description = "Private DNS zone providing WSFC/AG name resolution without Active Directory (env.conf PRIVATE_DNS_ZONE)."
  type        = string
  default     = "corp.internal"
}

variable "ag_listener_ip" {
  description = "Static IP the Always On AG listener will float on, published as aglistener.<zone> (env.conf LB_PRIVATE_IP)."
  type        = string
  default     = "10.10.1.200"
}

variable "wsfc_cluster_ip" {
  description = "Static IP reserved for the WSFC cluster name object, published as sqlcluster.<zone> (env.conf WSFC_CLUSTER_IP)."
  type        = string
  default     = "10.10.1.201"
}

# -----------------------------------------------------------------------------
# Storage (storage.sh)
# -----------------------------------------------------------------------------
# NOTE: this root declares NO storage resources. bootstrap/ owns the account, the
# four containers and the lab archive, and publishes them as outputs that data.tf
# reads back through terraform_remote_state. The variables below the first one are
# what storage.tf consumed before that move; see the comment on
# storage_default_action for which of them are still live.

variable "bootstrap_state_storage_account_name" {
  description = <<-EOT
    Storage account holding terraform_flat/bootstrap's remote state — the blob that
    data.terraform_remote_state.bootstrap reads.

    Only the account name is a variable. The container ("terraform-state-files") and
    key ("bootstrap.tfstate") are fixed by bootstrap/cleanup.sh:121-122, and the
    resource group is the same $primary_rg both roots already receive, so the
    remote-state config reuses var.resource_group_name.

    bootstrap/cleanup.sh discovers this name at runtime with
    `az storage account list --query "[0].name"` and writes it into
    bootstrap/backend.tf, so the default below tracks the CURRENT sandbox. After a
    rebuild, confirm it still matches:
      grep storage_account_name bootstrap/backend.tf

    A variable rather than the literal terraform/data.tf:13 hardcodes — that copy
    has already drifted to a resource group that no longer exists.
  EOT
  type        = string
  default     = "dp300ts"
}

variable "storage_account_name" {
  description = <<-EOT
    Storage account name (env.conf STORAGE_ACCOUNT_NAME). This is a GLOBALLY unique
    name in Azure — if the sandbox is rebuilt and the name has been claimed
    elsewhere, apply fails and a new value must be supplied here.
  EOT
  type        = string
  default     = "storage69987"

  validation {
    condition     = can(regex("^[a-z0-9]{3,24}$", var.storage_account_name))
    error_message = "storage_account_name must be 3-24 lowercase alphanumeric characters."
  }
}


variable "backup_container_name" {
  description = "Container holding SQL backups and the DP-300 lab archive (env.conf CONTAINER_NAME)."
  type        = string
  default     = "sqlbackups"
}


variable "xevent_container_name" {
  description = "Container that Extended Events sessions write to (env.conf XEVENT_CONTAINER_NAME)."
  type        = string
  default     = "xevents"
}


variable "xevent_policy_name" {
  description = "Stored access policy on the XEvent container (storage.sh:311). No azurerm resource exists; applied via CLI shim."
  type        = string
  default     = "xevent-policy-v3"
}

variable "xevent_policy_expiry" {
  description = "Expiry of the XEvent stored access policy (storage.sh:313)."
  type        = string
  default     = "2030-12-31T23:59:00Z"
}

variable "storage_default_action" {
  description = <<-EOT
    Final firewall posture of the storage account (storage.sh:341 sets Deny). This
    is exposed as a variable specifically as a rescue lever: once the account is
    locked to Deny, a later apply from a DIFFERENT client IP fails while the
    provider refreshes the container/blob data plane. Recover with
    `terraform apply -var=storage_default_action=Allow` followed by a normal apply.
  EOT
  type        = string
  default     = "Deny"

  validation {
    condition     = contains(["Allow", "Deny"], var.storage_default_action)
    error_message = "storage_default_action must be Allow or Deny."
  }
}

variable "blob_soft_delete_days" {
  description = "Blob soft-delete retention in days (storage.sh:292)."
  type        = number
  default     = 14
}

variable "lab_archive_path" {
  description = <<-EOT
    Local path to the DP-300 lab archive uploaded to the backup container
    (env.conf BLOB_NAME / LOCAL_FILE_PATH). The file is ~119 MB and docs/lab-files/
    is gitignored, so the blob resource is gated on fileexists() and simply plans to
    zero resources on a checkout that does not have it.
  EOT
  type        = string
  default     = "../docs/lab-files/dp-300-database-administrator-master.zip"
}

variable "lab_blob_sas_hours" {
  description = "Lifetime of the read/write SAS minted for the lab archive, in hours (vm-config.sh mints 7 days)."
  type        = number
  default     = 168
}

# -----------------------------------------------------------------------------
# Key Vault (key-vault.sh)
# -----------------------------------------------------------------------------

variable "key_vault_sku" {
  description = "Key Vault SKU (key-vault.sh:17)."
  type        = string
  default     = "standard"
}

variable "key_vault_soft_delete_days" {
  description = "Key Vault soft-delete retention in days (key-vault.sh:18)."
  type        = number
  default     = 7
}

variable "kv_purge_protection" {
  description = <<-EOT
    Enable Key Vault purge protection (key-vault.sh:19 sets this true). WARNING: this
    is IRREVERSIBLE. With it on, `terraform destroy` leaves a soft-deleted vault
    occupying the name for key_vault_soft_delete_days, which blocks a re-apply under
    the same name. Set false for short-lived sandbox rebuilds.
  EOT
  type        = bool
  default     = true
}

# -----------------------------------------------------------------------------
# Windows SQL nodes (win-sql-vm.sh / win-sql-vm-2.sh)
# -----------------------------------------------------------------------------

variable "win_vm_size" {
  description = "SQL Node 1 VM size (env.conf WIN_VM_SIZE)."
  type        = string
  default     = "Standard_D8s_v3"
}

variable "win_vm_size_2" {
  description = "SQL Node 2 VM size (env.conf WIN_VM_SIZE_2). Intentionally smaller than node 1 to fit sandbox quota."
  type        = string
  default     = "Standard_B2ms"
}

variable "win_image" {
  description = <<-EOT
    Windows Server platform image for both SQL nodes (env.conf WIN_IMAGE). This is a
    BASE Windows image, not a SQL Server marketplace image — SQL Server 2022
    Developer and SSMS are installed later by ansible/playbooks/sql-server-on-windows.yml,
    which avoids needing marketplace plan acceptance in the sandbox.
  EOT
  type = object({
    publisher = string
    offer     = string
    sku       = string
    version   = string
  })
  default = {
    publisher = "MicrosoftWindowsServer"
    offer     = "WindowsServer"
    sku       = "2022-datacenter-azure-edition"
    version   = "latest"
  }
}

variable "win_os_disk_type" {
  description = "OS disk SKU for both Windows nodes (win-sql-vm.sh:51)."
  type        = string
  default     = "StandardSSD_ZRS"
}

variable "win_data_disk_sku" {
  description = "SKU for the Windows data/log/tempdb/backup disks (env.conf WIN_DISK_SKU). LRS because the disks are zonal."
  type        = string
  default     = "StandardSSD_LRS"
}

variable "win_disk_sizes" {
  description = "Windows SQL data disk sizes in GB, keyed by role (env.conf WIN_*_DISK_SIZE)."
  type = object({
    data   = number
    log    = number
    tempdb = number
    backup = number
  })
  default = {
    data   = 4022
    log    = 2011
    tempdb = 1024
    backup = 8124
  }
}

variable "winrm_https_port" {
  description = "WinRM HTTPS listener port Ansible connects on (env.conf HTTPS_WIN_WINRM_PORT)."
  type        = number
  default     = 5986
}

variable "winrm_http_port" {
  description = "WinRM HTTP listener port, kept open as an NSG-scoped fallback (env.conf WIN_WINRM_PORT)."
  type        = number
  default     = 5985
}

# -----------------------------------------------------------------------------
# Linux application VM (app-vm.sh / encrypted-mgd-disks.sh) — gated
# -----------------------------------------------------------------------------

variable "linux_vm_size" {
  description = "Linux application VM size (env.conf VM_SIZE)."
  type        = string
  default     = "Standard_B2ms"
}

variable "linux_image" {
  description = "RHEL image for the Linux application VM (env.conf IMAGE)."
  type = object({
    publisher = string
    offer     = string
    sku       = string
    version   = string
  })
  default = {
    publisher = "RedHat"
    offer     = "RHEL"
    sku       = "9-lvm-gen2"
    version   = "latest"
  }
}

variable "linux_os_disk_size_gb" {
  description = "Linux OS disk size in GB (app-vm.sh:42)."
  type        = number
  default     = 512
}

variable "linux_disk_sizes" {
  description = <<-EOT
    Linux managed disk sizes in GB (encrypted-mgd-disks.sh). Deliberately different
    from the Windows sizing, and the disks are ZRS + non-zonal rather than LRS +
    zonal — preserved exactly as the script had them rather than harmonised.
  EOT
  type = object({
    data   = number
    log    = number
    tempdb = number
    backup = number
  })
  default = {
    data   = 4028
    log    = 2048
    tempdb = 1024
    backup = 4096
  }
}

variable "linux_disk_sku" {
  description = "SKU for the Linux managed disks (encrypted-mgd-disks.sh:50). ZRS, since these disks are non-zonal."
  type        = string
  default     = "StandardSSD_ZRS"
}

# -----------------------------------------------------------------------------
# PHASE 5 — Azure SQL Database (sql-db.sh and friends)
# -----------------------------------------------------------------------------

variable "sql_database_name" {
  description = "Azure SQL database name (env.conf DATABASE_NAME)."
  type        = string
  default     = "demo-db"
}

variable "sql_database_sku" {
  description = "Azure SQL database SKU (sql-db.sh:145 uses --edition Basic)."
  type        = string
  default     = "Basic"
}

variable "sql_database_max_size_gb" {
  description = "Azure SQL database max size in GB (sql-db.sh:146)."
  type        = number
  default     = 2
}

variable "entra_admin_login" {
  description = <<-EOT
    UPN of the Microsoft Entra administrator for the SQL server — db-deploy.sh
    STEP 14 (set-entra-admin.sh), which reads it from
    `az ad signed-in-user show --query userPrincipalName`. Terraform cannot resolve
    this without the azuread provider, so it is an explicit input. Leave empty to
    skip setting an Entra admin.
  EOT
  type        = string
  default     = ""
}

variable "entra_admin_object_id" {
  description = <<-EOT
    Object ID of the Entra administrator. Defaults to the object ID of whoever is
    running Terraform, which is correct in the sandbox because the only supported
    auth mode is an interactive `az login` as a user.
  EOT
  type        = string
  default     = ""
}

variable "log_analytics_name" {
  description = "Log Analytics workspace receiving SQL audit and diagnostic data (env.conf LAW_NAME)."
  type        = string
  default     = "sql-audit-law"
}

variable "log_retention_days" {
  description = "Retention in days for auditing, diagnostics and the workspace (env.conf RETENTION_DAYS)."
  type        = number
  default     = 30
}

variable "backup_short_term_retention_days" {
  description = "Point-in-time restore retention in days (sqldb-backup.sh:33)."
  type        = number
  default     = 7
}

variable "backup_diff_interval_hours" {
  description = "Differential backup interval in hours (sqldb-backup.sh:34)."
  type        = number
  default     = 24
}

variable "backup_ltr" {
  description = "Long-term retention policy (env.conf WEEKLY_/MONTHLY_/YEARLY_RETENTION and WEEK_OF_YEAR)."
  type = object({
    weekly       = string
    monthly      = string
    yearly       = string
    week_of_year = number
  })
  default = {
    weekly       = "P12W"
    monthly      = "P12M"
    yearly       = "P7Y"
    week_of_year = 26
  }
}

variable "alert_email" {
  description = "Email address the SQL action group notifies (env.conf ALERT_EMAIL)."
  type        = string
  default     = "hardeymolhar@gmail.com"
}

variable "sql_automatic_tuning_mode" {
  description = "Desired automatic tuning state applied by the CLI shim (STEP 18). One of Inherit, Auto, Custom, Unspecified."
  type        = string
  default     = "Auto"

  validation {
    condition     = contains(["Inherit", "Auto", "Custom", "Unspecified"], var.sql_automatic_tuning_mode)
    error_message = "sql_automatic_tuning_mode must be one of Inherit, Auto, Custom, Unspecified."
  }
}

# -----------------------------------------------------------------------------
# Ansible hand-off
# -----------------------------------------------------------------------------

variable "sql_installer_url" {
  description = "SQL Server 2022 Developer bootstrapper the Windows play downloads (env.conf SQL_INSTALLER_URL)."
  type        = string
  default     = "https://aka.ms/sqlserver2022developer"
}

variable "identity_propagation_delay" {
  description = <<-EOT
    How long to wait after a managed identity is created before granting it Key Vault
    access. Replaces the fixed `sleep 30` in sql-db.sh:185 and the nslookup polling
    loop in key-vault.sh:55-63; mirrors the 90s time_sleep already used in
    terraform/modules/security/main.tf.
  EOT
  type        = string
  default     = "90s"
}
