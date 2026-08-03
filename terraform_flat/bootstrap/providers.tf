# =============================================================================
# PROVIDER CONFIGURATION
# -----------------------------------------------------------------------------
# resource_provider_registrations = "none" is the azurerm 4.x replacement for the
# old skip_provider_registration flag. It is required here for the same reason it
# is set in the modular root: the Whizlabs sandbox subscription is identity
# restricted, so the signed-in principal cannot register resource providers and
# any attempt to do so fails the whole plan.
#
# purge_soft_deleted_keys_on_destroy is left at its default (true) but recovery is
# enabled, so a `terraform destroy` followed by a re-apply reuses the soft-deleted
# CMK/TDE/DES keys instead of colliding with them. Note this does NOT rescue the
# Key Vault itself — purge protection on the vault is irreversible (see README).
# =============================================================================

provider "azurerm" {
  features {
    key_vault {
      recover_soft_deleted_keys    = true
      recover_soft_deleted_secrets = true
    }
  }

  resource_provider_registrations = "none"
  subscription_id                 = var.subscription_id
}
