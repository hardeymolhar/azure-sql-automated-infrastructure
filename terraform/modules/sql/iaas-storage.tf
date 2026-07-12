# =====================================================
# IaaS SQL-on-VM track — witness/backup storage account (shell parity)
# -----------------------------------------------------
# Mirrors scripts/shell/test-env/storage.sh END STATE. The script opens the
# firewall (default-action Allow) for its data-plane provisioning and locks it
# to Deny as the final step; Terraform declares the final state directly:
# reachable, but only from the client IP, the VM subnets, and trusted Azure
# services. shared_access_key_enabled stays true — WSFC Cloud Witness and the
# lab-file SAS downloads authenticate with the account key, not Entra.
#
# Deliberately NOT reproduced from storage.sh (documented exclusions):
#   - blob upload of dp-300-database-administrator-master.zip (:161) —
#     data-plane content; the 200 MB source archive is gitignored. Upload
#     remains a manual/script step after apply.
#   - stored access policy xevent-policy-v3 (:308) — container stored access
#     policies have no azurerm resource (verified against provider docs); its
#     only consumer (identity.sh) is outside the migration scope. Keep
#     creating it via storage.sh if/when XEvents offloading is used.
# =====================================================

resource "azurerm_storage_account" "iaas" {
  count = var.iaas_enabled ? 1 : 0

  name                = var.iaas_storage_account_name
  resource_group_name = var.iaas_rg
  location            = var.iaas_location

  account_tier             = "Standard"
  account_replication_type = "LRS"
  account_kind             = "StorageV2"

  https_traffic_only_enabled      = true
  min_tls_version                 = "TLS1_2"
  allow_nested_items_to_be_public = false
  public_network_access_enabled   = true
  shared_access_key_enabled       = true

  network_rules {
    default_action             = "Deny"
    bypass                     = ["AzureServices"]
    ip_rules                   = [var.client_ip]
    virtual_network_subnet_ids = var.iaas_storage_subnet_ids
  }

  blob_properties {
    versioning_enabled = true

    delete_retention_policy {
      days = 14
    }
  }
}

resource "azurerm_storage_container" "iaas_sqlbackups" {
  count = var.iaas_enabled ? 1 : 0

  name                  = "sqlbackups"
  storage_account_id    = azurerm_storage_account.iaas[0].id
  container_access_type = "private"
}

resource "azurerm_storage_container" "iaas_xevents" {
  count = var.iaas_enabled ? 1 : 0

  name                  = "xevents"
  storage_account_id    = azurerm_storage_account.iaas[0].id
  container_access_type = "private"
}
