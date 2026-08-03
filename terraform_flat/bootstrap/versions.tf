# =============================================================================
# TERRAFORM + PROVIDER VERSIONS
# -----------------------------------------------------------------------------
# This root previously declared NO terraform{} block at all, so `terraform init`
# resolved every provider unconstrained and picked up azurerm 5.0.1 — while the
# root one level up pins 4.75.0 exactly and both terraform/ and the repo-root
# bootstrap/ ask for "~> 4.0". One root on a different major is how a state file
# ends up readable by only one working copy.
#
# Pinning back to 4.75.0 is state-safe, and that was checked rather than assumed:
# `terraform providers schema -json` against the cached 4.75.0 binary reports
# azurerm_storage_account at schema_version 4 and azurerm_storage_container at 1,
# and the instances azurerm 5.0.1 wrote into terraform.tfstate carry exactly those
# numbers. No schema regression, so nothing is stranded.
#
# The one config consequence: 4.75.0's azurerm_storage_blob has no
# `storage_container_id` — that argument is the 5.0 replacement for the
# storage_account_name/storage_container_name pair. Both blob resources in
# storage.tf use the 4.x pair for that reason.
#
# `random` IS declared here, unlike terraform_flat/versions.tf which deliberately
# omits it: locals.tf generates the storage account name suffix with
# random_string.kv_suffix, so this root genuinely needs the provider.
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
    time = {
      source  = "hashicorp/time"
      version = "~> 0.13"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.9"
    }
  }

  required_version = ">= 1.4.0"
}
