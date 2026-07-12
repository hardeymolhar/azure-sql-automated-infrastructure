# =====================================================
# IaaS SQL-on-VM track — Key Vault khv-<suffix> (shell parity)
# -----------------------------------------------------
# Mirrors scripts/shell/test-env/key-vault.sh. Separate vault from the PaaS
# kv-<name_suffix>: access-policy mode (not RBAC), deny-by-default firewall
# with the operator client IP plus the IaaS Linux VM's public IP (the shell
# adds the VM IP later, in app-vm.sh:200; Key Vault ip_rules are inline-only
# in azurerm, so both are set at creation — same end state).
#
# The operator access policy replaces the implicit creator-permissions policy
# `az keyvault create` grants; without it Terraform cannot create the keys and
# secrets below in an access-policy-mode vault.
# =====================================================

resource "azurerm_key_vault" "iaas" {
  count = var.iaas_enabled ? 1 : 0

  name                = "khv-${var.iaas_resource_suffix}"
  location            = var.iaas_location
  resource_group_name = var.iaas_rg
  tenant_id           = data.azurerm_client_config.current.tenant_id
  sku_name            = "standard"

  soft_delete_retention_days = 7
  purge_protection_enabled   = true

  public_network_access_enabled = true
  network_acls {
    default_action = "Deny"
    bypass         = "AzureServices"
    ip_rules       = compact([var.client_ip, var.iaas_linux_vm_public_ip])
  }
}

resource "azurerm_key_vault_access_policy" "iaas_operator" {
  count = var.iaas_enabled ? 1 : 0

  key_vault_id = azurerm_key_vault.iaas[0].id
  tenant_id    = data.azurerm_client_config.current.tenant_id
  object_id    = data.azurerm_client_config.current.object_id

  key_permissions = [
    "Get", "List", "Create", "Update", "Delete", "Recover", "Backup", "Restore",
    "WrapKey", "UnwrapKey", "Encrypt", "Decrypt", "Sign", "Verify",
    "Purge", "Release", "Rotate", "GetRotationPolicy", "SetRotationPolicy"
  ]

  secret_permissions      = ["Get", "List", "Set", "Delete", "Recover", "Backup", "Restore", "Purge"]
  certificate_permissions = ["Get", "List", "Create", "Update", "Delete", "Recover", "Backup", "Restore", "Purge"]
}

# =====================================================
# Keys (key-vault.sh:67-113) — names and key_opts verbatim
# =====================================================

resource "azurerm_key_vault_key" "iaas_column_master_key" {
  count = var.iaas_enabled ? 1 : 0

  name         = "column-master-key"
  key_vault_id = azurerm_key_vault.iaas[0].id
  key_type     = "RSA"
  key_size     = 2048

  key_opts = ["wrapKey", "unwrapKey", "sign", "verify"]

  depends_on = [azurerm_key_vault_access_policy.iaas_operator]
}

resource "azurerm_key_vault_key" "iaas_tde_key" {
  count = var.iaas_enabled ? 1 : 0

  name         = "tde-encrypted-key"
  key_vault_id = azurerm_key_vault.iaas[0].id
  key_type     = "RSA"
  key_size     = 2048

  key_opts = ["wrapKey", "unwrapKey", "sign", "verify", "encrypt", "decrypt"]

  depends_on = [azurerm_key_vault_access_policy.iaas_operator]
}

resource "azurerm_key_vault_key" "iaas_des_key" {
  count = var.iaas_enabled ? 1 : 0

  name         = "disk-encryption-set-key"
  key_vault_id = azurerm_key_vault.iaas[0].id
  key_type     = "RSA"
  key_size     = 2048

  key_opts = ["wrapKey", "unwrapKey"]

  depends_on = [azurerm_key_vault_access_policy.iaas_operator]
}

# =====================================================
# Secrets (key-vault.sh:115-160) — admin password + SSH keypair
# =====================================================

resource "azurerm_key_vault_secret" "iaas_sql_admin_password" {
  count = var.iaas_enabled ? 1 : 0

  name         = "sql-admin-password"
  value        = var.iaas_admin_password
  key_vault_id = azurerm_key_vault.iaas[0].id

  depends_on = [azurerm_key_vault_access_policy.iaas_operator]
}

resource "azurerm_key_vault_secret" "iaas_ssh_private_key" {
  count = var.iaas_enabled ? 1 : 0

  name         = "vm-ssh-private-key"
  value        = file(pathexpand("~/.ssh/ssh_key/vm-key/vm-key"))
  key_vault_id = azurerm_key_vault.iaas[0].id

  depends_on = [azurerm_key_vault_access_policy.iaas_operator]
}

resource "azurerm_key_vault_secret" "iaas_ssh_public_key" {
  count = var.iaas_enabled ? 1 : 0

  name         = "vm-ssh-public-key"
  value        = file(pathexpand("~/.ssh/ssh_key/vm-key/vm-key.pub"))
  key_vault_id = azurerm_key_vault.iaas[0].id

  depends_on = [azurerm_key_vault_access_policy.iaas_operator]
}
