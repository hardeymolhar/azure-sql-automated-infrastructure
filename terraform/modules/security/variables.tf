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

variable "client_ip" {
  type = string
}

# ========================================
# Wiring from the SQL module
# ========================================

variable "name_suffix" {
  description = "Random suffix for naming the Key Vault (from the sql module)"
  type        = string
}

variable "sql_server_id" {
  description = "ID of the primary SQL Server"
  type        = string
}

variable "sql_identity_tenant_id" {
  description = "Tenant ID of the primary SQL Server managed identity"
  type        = string
}

variable "sql_identity_principal_id" {
  description = "Principal ID of the primary SQL Server managed identity"
  type        = string
}

variable "sql_secondary_server_id" {
  description = "ID of the secondary SQL Server"
  type        = string
}

variable "sql_secondary_identity_tenant_id" {
  description = "Tenant ID of the secondary SQL Server managed identity"
  type        = string
}

variable "sql_secondary_identity_principal_id" {
  description = "Principal ID of the secondary SQL Server managed identity"
  type        = string
}