# =============================================================================
# TERRAFORM + PROVIDER VERSIONS
# -----------------------------------------------------------------------------
# Pins are deliberately identical to the modular root (terraform/providers.tf):
# azurerm is pinned EXACTLY to 4.75.0 rather than "~> 4.0" so both roots resolve
# to the same provider build that terraform/.terraform.lock.hcl already records.
# Every resource in this root was schema-checked against that exact binary.
#
# required_version >= 1.4.0 is what the rest of the repo declares, and it is also
# the floor for `terraform_data` — the built-in lifecycle resource this root uses
# for the two shims where no azurerm resource exists (see main.tf). Using
# terraform_data instead of hashicorp/null keeps the provider set to five, all of
# which are already cached, so `terraform init -backend=false` works offline.
# =============================================================================

terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "4.75.0"
    }
    http = {
      source  = "hashicorp/http"
      version = "~> 3.0"
    }
    # `time` supplies time_sleep, used in security.tf and database.tf to wait out
    # Azure AD replication after a managed identity is minted. It also supplied
    # time_rotating for the lab-archive SAS window until storage moved to
    # bootstrap/, which now owns that resource. random/tls/local are deliberately
    # NOT declared: every name in this root is deterministic from
    # var.resource_suffix, and nothing is generated on disk.
    time = {
      source  = "hashicorp/time"
      version = "~> 0.13"
    }
  }

  required_version = ">= 1.4.0"
}
