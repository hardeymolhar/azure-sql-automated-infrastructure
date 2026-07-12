# =====================================================
# IaaS SQL-on-VM track (shell parity) — module inputs
# Source of truth: scripts/shell/test-env/storage.sh. The storage account
# lives in the sql module because its lifecycle serves SQL backups
# (sqlbackups), SQL diagnostics (xevents), and the WSFC Cloud Witness.
# =====================================================

variable "iaas_enabled" {
  description = "Deploy the IaaS SQL-on-VM track resources owned by this module. Off by default."
  type        = bool
  default     = false
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

variable "iaas_storage_account_name" {
  description = "Globally-unique name of the witness/backup storage account (env.conf STORAGE_ACCOUNT_NAME). Change it if the shell-built original still exists."
  type        = string
  default     = "storage69987"
}

variable "iaas_storage_subnet_ids" {
  description = "Subnet ids allowed through the storage firewall (network module output; storage.sh:201 allows subnet-win + the main subnet — the Windows rule is what Cloud Witness relies on)."
  type        = list(string)
  default     = []
}
