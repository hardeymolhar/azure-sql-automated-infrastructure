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
# Storage (storage.sh)
# -----------------------------------------------------------------------------


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
    Local path to the DP-300 lab archive uploaded to the lab-resources container
    (env.conf BLOB_NAME / LOCAL_FILE_PATH). The file is ~119 MB and docs/lab-files/
    is gitignored, so the blob resource is gated on fileexists() and simply plans to
    zero resources on a checkout that does not have it.

    TWO levels up, not one: this variable was copied from terraform_flat/, where
    "../docs/lab-files" is correct. From terraform_flat/bootstrap/ that same string
    resolves to terraform_flat/docs/lab-files/, which does not exist — fileexists()
    would quietly return false and the archive would never upload.
  EOT
  type        = string
  default     = "../../docs/lab-files/dp-300-database-administrator-master.zip"
}

variable "lab_blob_sas_hours" {
  description = "Lifetime of the read/write SAS minted for the lab archive, in hours (vm-config.sh mints 7 days)."
  type        = number
  default     = 168
}


