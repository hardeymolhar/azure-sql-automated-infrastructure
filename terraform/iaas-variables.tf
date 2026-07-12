# =====================================================
# IaaS SQL-on-VM track (shell parity) — root inputs
# -----------------------------------------------------
# Terraform port of the scripts/shell/test-env/ db-deploy.sh pipeline
# (SQL Server 2022 on zonal Windows VMs + WSFC/Always On AG + dual AD DS
# domain controllers + internal LB listener + CMK-encrypted disks).
# Everything is gated behind iaas_enabled: with the default (false) the plan
# is byte-identical to the pre-IaaS configuration. To deploy, set in tfvars:
#   iaas_enabled        = true
#   iaas_rg             = "<sandbox resource group>"
#   iaas_admin_password = "<admin password>"
# (see iaas.tfvars.example). In-guest configuration (AD promotion, WSFC,
# AG, SQL install) remains Ansible via vm-config-orchestrator.sh — Terraform
# replaces Phases 1-3 of db-deploy.sh only.
# =====================================================

variable "iaas_enabled" {
  description = "Deploy the IaaS SQL-on-VM track. Off by default: the existing PaaS plan is unchanged until enabled."
  type        = bool
  default     = false
}

variable "iaas_resource_suffix" {
  description = "Name suffix mirroring env.conf RESOURCE_SUFFIX so the shell/Ansible tooling's name lookups keep working."
  type        = string
  default     = "res-ind-442"
}

variable "iaas_rg" {
  description = "Existing resource group for the IaaS track (the shell resolves this at runtime via 'az group list [1]'). Required when iaas_enabled = true."
  type        = string
  default     = null
}

variable "iaas_location" {
  description = "Region for the IaaS track (env.conf LOCATION)."
  type        = string
  default     = "centralindia"
}

variable "iaas_admin_username" {
  description = "Admin user for every IaaS VM (env.conf ADMIN_USERNAME)."
  type        = string
  default     = "sqladmin"
}

variable "iaas_admin_password" {
  description = "Shared admin password for the IaaS VMs and the sql-admin-password vault secret (env.conf ADMIN_PASSWORD). Required when iaas_enabled = true."
  type        = string
  sensitive   = true
  default     = null
}

variable "iaas_storage_account_name" {
  description = "Globally-unique witness/backup storage account name (env.conf STORAGE_ACCOUNT_NAME). Change if the shell-built original still exists."
  type        = string
  default     = "storage69987"
}
