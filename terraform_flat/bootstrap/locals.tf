# =============================================================================
# COMPUTED VALUES
# -----------------------------------------------------------------------------
# This file is the whole of what var-config.sh used to do. That script existed
# only to rewrite name suffixes in place across every .sh/.ps1 with
#   perl -pi -e "s/(vm|vnet|subnet|...)-[a-zA-Z0-9-]+/\1-$NEW_ID/g"
# which is also where artefacts like private-dns.sh:27's "vnet-stg-ind-49stg-ind-49"
# (a double substitution) came from. Deriving every name from one variable removes
# both the script and the class of bug.
# =============================================================================
resource "random_string" "kv_suffix" {

  length  = 2
  lower   = true
  upper   = false
  special = false
  numeric = false
}


locals {
  suffix               = var.resource_suffix
  storage_account_name = "dp300${random_string.kv_suffix.result}"


  # The public IP Terraform is running from. Used as the allowed source for every
  # RDP/WinRM/SQL NSG rule, the Key Vault and storage IP rules, and the SQL server
  # firewall rule — the same single-client-IP allowlist model env.conf built with
  # `curl -4 -s https://api.ipify.org`.
  client_ip = chomp(data.http.client_ip.response_body)

  # The DP-300 lab archive. fileexists() rather than a feature flag: docs/lab-files/
  # is gitignored, so a fresh checkout has no archive and the blob must plan to zero
  # resources instead of failing on a missing source file. Mirrors
  # terraform_flat/locals.tf:49-50, which is where these lived before storage moved
  # into this root.
  lab_blob_name         = basename(var.lab_archive_path)
  lab_archive_available = fileexists(var.lab_archive_path)

}