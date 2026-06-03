variable "primary_rg" {
  type = string
}

variable "secondary_rg" {
  type = string
}

variable "primary_location" {
  type = string
}

variable "secondary_location" {
  type = string
}

# ========================================
# Wiring from network / security / sql modules
# ========================================

variable "pe_subnet_id" {
  description = "ID of the private-endpoint subnet (from the network module)"
  type        = string
}

variable "key_vault_id" {
  description = "ID of the Key Vault (from the security module)"
  type        = string
}

variable "sql_server_id" {
  description = "ID of the primary SQL Server (from the sql module)"
  type        = string
}

variable "vault_dns_zone_id" {
  description = "ID of the Key Vault private DNS zone (from the network module)"
  type        = string
}

variable "sql_dns_zone_id" {
  description = "ID of the SQL private DNS zone (from the network module)"
  type        = string
}