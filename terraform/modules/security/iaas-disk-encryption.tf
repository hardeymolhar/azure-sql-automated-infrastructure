# =====================================================
# IaaS SQL-on-VM track — Disk Encryption Sets (SSE with CMK)
# -----------------------------------------------------
# Two DES, both wrapping the same Key Vault key (disk-encryption-set-key):
#   winsql-des-<suffix> — Windows SQL nodes (win-encrypted-disks*.sh:66),
#                         dedicated so the Windows workload is isolated
#   sql-des-<suffix>    — Linux workload VM  (encrypted-mgd-disks.sh:22)
# Each DES gets a system identity that must hold Get/WrapKey/UnwrapKey on the
# vault BEFORE any disk is created against it — the vm module consumes the DES
# ids via outputs whose depends_on pins that ordering.
# =====================================================

resource "azurerm_disk_encryption_set" "iaas_windows" {
  count = var.iaas_enabled ? 1 : 0

  name                = "winsql-des-${var.iaas_resource_suffix}"
  location            = var.iaas_location
  resource_group_name = var.iaas_rg
  key_vault_key_id    = azurerm_key_vault_key.iaas_des_key[0].id

  identity {
    type = "SystemAssigned"
  }
}

resource "azurerm_key_vault_access_policy" "iaas_windows_des" {
  count = var.iaas_enabled ? 1 : 0

  key_vault_id = azurerm_key_vault.iaas[0].id
  tenant_id    = azurerm_disk_encryption_set.iaas_windows[0].identity[0].tenant_id
  object_id    = azurerm_disk_encryption_set.iaas_windows[0].identity[0].principal_id

  key_permissions = ["Get", "WrapKey", "UnwrapKey"]
}

resource "azurerm_disk_encryption_set" "iaas_linux" {
  count = var.iaas_enabled ? 1 : 0

  name                = "sql-des-${var.iaas_resource_suffix}"
  location            = var.iaas_location
  resource_group_name = var.iaas_rg
  key_vault_key_id    = azurerm_key_vault_key.iaas_des_key[0].id

  identity {
    type = "SystemAssigned"
  }
}

resource "azurerm_key_vault_access_policy" "iaas_linux_des" {
  count = var.iaas_enabled ? 1 : 0

  key_vault_id = azurerm_key_vault.iaas[0].id
  tenant_id    = azurerm_disk_encryption_set.iaas_linux[0].identity[0].tenant_id
  object_id    = azurerm_disk_encryption_set.iaas_linux[0].identity[0].principal_id

  key_permissions = ["Get", "WrapKey", "UnwrapKey"]
}
