# =====================================================
# IaaS SQL-on-VM track (shell parity) — module inputs
# -----------------------------------------------------
# Source of truth: scripts/shell/test-env/ (the db-deploy.sh pipeline).
# Every iaas_* resource in this module is gated behind iaas_enabled
# (default false) so the existing PaaS plan is unchanged until the
# operator explicitly opts in via tfvars.
# =====================================================

variable "iaas_enabled" {
  description = "Deploy the IaaS SQL-on-VM track (parity with scripts/shell/test-env). Off by default: the existing plan is byte-identical until enabled."
  type        = bool
  default     = false
}

variable "iaas_resource_suffix" {
  description = "Name suffix mirroring env.conf RESOURCE_SUFFIX so the vm-config-*/Ansible name lookups keep working against Terraform-built resources."
  type        = string
  default     = "res-ind-442"
}

variable "iaas_rg" {
  description = "Resource group for the IaaS track. env.conf resolves this at runtime (az group list [1]); Terraform requires it explicitly. Must be set when iaas_enabled = true."
  type        = string
  default     = null
}

variable "iaas_location" {
  description = "Region for the IaaS track (env.conf LOCATION)."
  type        = string
  default     = "centralindia"
}
