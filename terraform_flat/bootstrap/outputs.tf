# =============================================================================
# OUTPUTS — the contract this root publishes to terraform_flat/
# -----------------------------------------------------------------------------
# This root owns every storage resource in the estate. The flat root one level up
# owns none of them, but its outputs.tf still has to report the account, the
# containers and the lab archive to vm-config.sh and both Ansible plays.
#
# Terraform roots cannot reference each other's managed resources, so everything
# the flat root needs has to leave here as an OUTPUT and be read back through
# `data "terraform_remote_state" "bootstrap"` (see terraform_flat/data.tf). An
# output that is missing here is a "Reference to undeclared resource" error there
# — which is exactly how this file came to be incomplete.
#
# Anything added below is part of a published interface. Renaming an output is a
# breaking change for the flat root and for `terraform output -raw` in
# vm-config.sh; add a new one instead.
# =============================================================================

# -----------------------------------------------------------------------------
# Storage account
# -----------------------------------------------------------------------------

output "storage_account_id" {
  description = "Storage account resource ID."
  value       = azurerm_storage_account.bootstrap.id
}

output "storage_account_name" {
  description = "Storage account name. Globally unique; generated as dp300<suffix> by locals.tf."
  value       = azurerm_storage_account.bootstrap.name
}

output "primary_blob_endpoint" {
  description = "Blob service endpoint, e.g. https://dp300xx.blob.core.windows.net/."
  value       = azurerm_storage_account.bootstrap.primary_blob_endpoint
}

output "primary_connection_string" {
  description = "Account connection string, for tooling that authenticates with the account key rather than Entra ID."
  value       = azurerm_storage_account.bootstrap.primary_connection_string
  sensitive   = true
}

# -----------------------------------------------------------------------------
# Containers
# -----------------------------------------------------------------------------
# Maps keyed by the for_each key, which is also the container name:
#   terraform-state-files, lab-resources, xevents, backups
#
# Published as maps rather than four scalar outputs so that adding a container to
# the for_each set in storage.tf needs no change here and no change downstream.
# The flat root indexes them by name — container_names["backups"].

output "container_names" {
  description = "Container names keyed by purpose. Keys: terraform-state-files, lab-resources, xevents, backups."
  value       = { for k, c in azurerm_storage_container.containers : k => c.name }
}

output "container_ids" {
  description = "Container resource IDs keyed by purpose. Needed by anything declaring a blob against a container this root owns."
  value       = { for k, c in azurerm_storage_container.containers : k => c.id }
}

# -----------------------------------------------------------------------------
# DP-300 lab archive
# -----------------------------------------------------------------------------

output "lab_archive_uploaded" {
  description = "Whether the DP-300 lab archive was present locally and uploaded. False on a checkout without docs/lab-files/."
  value       = local.lab_archive_available
}

output "lab_blob_url" {
  description = "Blob URL of the lab archive WITHOUT a SAS. Empty string when the archive was not uploaded."
  value       = try(azurerm_storage_blob.lab_archive[0].url, "")
}

output "lab_blob_sas_url" {
  description = <<-EOT
    Full HTTPS URL with SAS for the DP-300 lab archive. Replaces vm-config.sh's
    `az storage blob generate-sas`. The SAS window is pinned by time_rotating (see
    data.tf), so this value is stable between rotations instead of changing on
    every plan.

    Falls back to an EMPTY STRING, not null, when the archive was not uploaded:
    `terraform output -raw` errors on a null value, which under `set -euo pipefail`
    would kill vm-config.sh on any checkout without docs/lab-files/. An empty
    string lets the run continue and the playbook skip the download — the same
    outcome the original script had when SAS generation produced nothing.
  EOT
  value       = try("${azurerm_storage_blob.lab_archive[0].url}${data.azurerm_storage_account_blob_container_sas.lab_archive.sas}", "")
  sensitive   = true
}
