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
# Shared Access Signature for the DP-300 lab archive
# -----------------------------------------------------------------------------
# Replaces vm-config.sh:76-93, which shelled out to `az storage account keys list`
# + GNU/BSD `date` arithmetic + `az storage blob generate-sas`.
#
# WHY time_rotating AND NOT timestamp():
#   The obvious `start = timestamp()` recomputes on every plan, so the SAS — and
#   therefore any output derived from it — shows a diff on every single run, which
#   trains reviewers to ignore diffs. time_rotating pins the window to a stored
#   value and advances it exactly once per rotation period, so the SAS is stable
#   between rotations and still never goes stale. The modular root's
#   terraform/modules/vm/data.tf has the timestamp() problem; this root does not.
#
# This data source performs NO network call: the SAS is computed locally from the
# account key. That matters because the storage account is firewalled to Deny by
# the time outputs are read.
resource "time_rotating" "lab_sas_window" {
  rotation_hours = var.lab_blob_sas_hours
}

data "azurerm_storage_account_blob_container_sas" "lab_archive" {
  connection_string = azurerm_storage_account.bootstrap.primary_connection_string
  container_name    = azurerm_storage_container.containers["lab-resources"].name
  https_only        = true

  start  = time_rotating.lab_sas_window.rfc3339
  expiry = time_rotating.lab_sas_window.rotation_rfc3339

  # Matches vm-config.sh's `--permissions rw`. The Windows play uses win_get_url
  # and the RHEL play uses get_url, so read is what is actually exercised; write
  # is preserved from the original for parity.
  permissions {
    read   = true
    write  = true
    add    = false
    create = false
    delete = false
    list   = false
  }
}
