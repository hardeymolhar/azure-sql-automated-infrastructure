# =============================================================================
# DATA SOURCES
# -----------------------------------------------------------------------------
# These replace the four commands env.conf executed at *source* time — a design
# that made every script's behaviour depend on the shell environment rather than
# on declared inputs, and that failed outright when `az vm list-ip-addresses`
# was called for a VM that did not exist yet (env.conf:72-76).
# =============================================================================

# Tenant ID, subscription ID and the object ID of whoever is running Terraform.
# Replaces env.conf's `az ad signed-in-user show --query id`.
data "azurerm_client_config" "current" {}

# The public IP Terraform is running from. Replaces env.conf's
# `curl -4 -s https://api.ipify.org`. Every NSG rule, the Key Vault and storage
# IP allowlists, and the SQL server firewall rule are scoped to this single
# address — the estate is never opened to 0.0.0.0/0.
data "http" "client_ip" {
  url = "https://api.ipify.org"
}

# -----------------------------------------------------------------------------
# Storage, owned by bootstrap/
# -----------------------------------------------------------------------------
# This root declares NO storage resources. The account, the four containers, the
# 119 MB DP-300 lab archive and the container SAS all live in
# terraform_flat/bootstrap/ and are read back here as outputs.
#
# WHY THIS DATA SOURCE EXISTS AT ALL:
#   Terraform roots cannot reference each other's managed resources. When storage
#   moved into bootstrap/, outputs.tf kept saying azurerm_storage_account.main and
#   the SAS data source that used to sit here kept saying
#   azurerm_storage_account.bootstrap — 17 "Reference to undeclared resource"
#   errors, because neither resource is declared in THIS root. terraform_remote_state
#   is the supported bridge, and it is already the pattern the modular root uses at
#   terraform/data.tf:9.
#
# CONSEQUENCE, stated plainly: this root now has a hard read dependency on
# bootstrap's state blob. `terraform plan` here FAILS if bootstrap has not been
# applied, or if its storage firewall does not admit the current client IP. The
# apply order is bootstrap/cleanup.sh first, this root second — not optional.
#
# Only the account name is parameterised; see var.bootstrap_state_storage_account_name
# for why the other three keys are literals.
data "terraform_remote_state" "bootstrap" {
  backend = "azurerm"

  config = {
    resource_group_name  = var.resource_group_name
    storage_account_name = var.bootstrap_state_storage_account_name
    container_name       = "terraform-state-files"
    key                  = "bootstrap.tfstate"
  }
}


