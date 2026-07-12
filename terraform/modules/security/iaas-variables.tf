# =====================================================
# IaaS SQL-on-VM track (shell parity) — module inputs
# Source of truth: scripts/shell/test-env/key-vault.sh,
# win-encrypted-disks*.sh, encrypted-mgd-disks.sh, app-vm.sh.
# =====================================================

variable "iaas_enabled" {
  description = "Deploy the IaaS SQL-on-VM track resources owned by this module. Off by default."
  type        = bool
  default     = false
}

variable "iaas_resource_suffix" {
  description = "Name suffix mirroring env.conf RESOURCE_SUFFIX (Key Vault khv-<suffix>, DES names)."
  type        = string
  default     = "res-ind-442"
}

variable "iaas_rg" {
  description = "Resource group for the IaaS track. Must be set when iaas_enabled = true."
  type        = string
  default     = null
}

variable "iaas_location" {
  description = "Region for the IaaS track (env.conf LOCATION)."
  type        = string
  default     = "centralindia"
}

variable "iaas_admin_password" {
  description = "Sandbox shared admin password (env.conf ADMIN_PASSWORD) — stored as the sql-admin-password Key Vault secret (key-vault.sh:122). Required when iaas_enabled = true."
  type        = string
  sensitive   = true
  default     = null
}

variable "iaas_linux_vm_public_ip" {
  description = "Static public IP of the IaaS Linux VM (network module output) — allowed through the Key Vault firewall so the VM's data-plane calls succeed (app-vm.sh:200). Known at PIP creation, so no security->vm cycle."
  type        = string
  default     = null
}
