# =============================================================================
# SECURITY — replaces key-vault.sh, and the DES half of win-encrypted-disks*.sh
#            and encrypted-mgd-disks.sh
# -----------------------------------------------------------------------------
# db-deploy.sh STEP 3, plus the encryption-set portion of STEPs 5, 8 and 10.
#
# This file owns the root of trust for the whole estate: the customer-managed keys
# that wrap the SQL TDE protector, the Always Encrypted column master key, and the
# disk encryption sets that encrypt every managed disk at rest.
#
# TWO CASING FOOTGUNS, called out because they produce confusing 403s at apply
# time rather than errors at plan time:
#   * azurerm_key_vault_key.key_opts uses camelCase   -> "wrapKey", "unwrapKey"
#   * azurerm_key_vault_access_policy.key_permissions uses TitleCase -> "WrapKey"
# They are different vocabularies for the same operations. Mixing them validates
# fine and fails at runtime.
# =============================================================================

resource "azurerm_key_vault" "main" {
  name                = local.key_vault_name
  location            = var.location
  resource_group_name = var.resource_group_name
  tenant_id           = data.azurerm_client_config.current.tenant_id
  sku_name            = var.key_vault_sku

  soft_delete_retention_days = var.key_vault_soft_delete_days

  # WARNING — IRREVERSIBLE. Once enabled, purge protection cannot be turned off,
  # `az keyvault purge` is refused, and the vault name stays reserved for the full
  # soft-delete window after a destroy. That means `terraform destroy` followed by
  # a re-apply inside that window fails with "vault name is already in use".
  # key-vault.sh:19 sets this true, so the default here matches; set
  # var.kv_purge_protection = false for a sandbox you expect to rebuild often.
  purge_protection_enabled = var.kv_purge_protection

  # Access-policy model, NOT RBAC — matching key-vault.sh's
  # --enable-rbac-authorization false. This is why every consumer below needs an
  # explicit azurerm_key_vault_access_policy rather than a role assignment; the
  # sandbox is identity-restricted and cannot grant RBAC roles to other identities.
  rbac_authorization_enabled = false

  # Required for the disk encryption sets to wrap their key.
  enabled_for_disk_encryption     = true
  enabled_for_deployment          = true
  enabled_for_template_deployment = true

  public_network_access_enabled = true

  network_acls {
    default_action = "Deny"
    bypass         = "AzureServices"
    ip_rules       = [local.client_ip]
  }

  tags = var.tags
}

# -----------------------------------------------------------------------------
# Terraform's own access policy
# -----------------------------------------------------------------------------
# MANDATORY and must exist before any key or secret. Because the vault is
# access-policy based with default_action = "Deny", the identity running Terraform
# has no implicit rights to its own vault — creating a key without this returns
# 403 Forbidden. This mirrors terraform/modules/security/main.tf:89.
resource "azurerm_key_vault_access_policy" "terraform" {
  key_vault_id = azurerm_key_vault.main.id
  tenant_id    = data.azurerm_client_config.current.tenant_id
  object_id    = data.azurerm_client_config.current.object_id

  key_permissions = [
    "Get", "List", "Create", "Update", "Delete", "Recover", "Backup", "Restore",
    "WrapKey", "UnwrapKey", "Encrypt", "Decrypt", "Sign", "Verify",
    "Purge", "Release", "Rotate", "GetRotationPolicy", "SetRotationPolicy",
  ]

  secret_permissions = [
    "Get", "List", "Set", "Delete", "Recover", "Backup", "Restore", "Purge",
  ]

  certificate_permissions = [
    "Get", "List", "Create", "Update", "Delete", "Recover", "Backup", "Restore", "Purge",
  ]
}

# -----------------------------------------------------------------------------
# Customer-managed keys — key-vault.sh:74-112
# -----------------------------------------------------------------------------
# Three keys with three deliberately different capability sets. They are separate
# keys rather than one shared key so that rotating or revoking the Always
# Encrypted CMK cannot take down disk encryption or TDE, and vice versa — blast
# radius is scoped per concern.

# Always Encrypted column master key. Needs sign/verify in addition to wrap/unwrap
# because the client driver signs the column encryption key metadata with it.
resource "azurerm_key_vault_key" "column_master_key" {
  name         = "column-master-key"
  key_vault_id = azurerm_key_vault.main.id
  key_type     = "RSA"
  key_size     = 2048
  key_opts     = ["wrapKey", "unwrapKey", "sign", "verify"]

  depends_on = [azurerm_key_vault_access_policy.terraform]
}

# Transparent Data Encryption protector for the Azure SQL server (PHASE 5).
resource "azurerm_key_vault_key" "tde" {
  name         = "tde-encrypted-key"
  key_vault_id = azurerm_key_vault.main.id
  key_type     = "RSA"
  key_size     = 2048
  key_opts     = ["wrapKey", "unwrapKey", "sign", "verify", "encrypt", "decrypt"]

  depends_on = [azurerm_key_vault_access_policy.terraform]
}

# Wrapped by both disk encryption sets. Only needs wrap/unwrap — a DES never signs.
resource "azurerm_key_vault_key" "disk_encryption" {
  name         = "disk-encryption-set-key"
  key_vault_id = azurerm_key_vault.main.id
  key_type     = "RSA"
  key_size     = 2048
  key_opts     = ["wrapKey", "unwrapKey"]

  depends_on = [azurerm_key_vault_access_policy.terraform]
}

# -----------------------------------------------------------------------------
# Secrets — key-vault.sh:122-159
# -----------------------------------------------------------------------------

resource "azurerm_key_vault_secret" "sql_admin_password" {
  name         = "sql-admin-password"
  value        = var.admin_password
  key_vault_id = azurerm_key_vault.main.id

  depends_on = [azurerm_key_vault_access_policy.terraform]
}

# The SSH keypair secrets are gated on the key files actually existing. This is
# not defensive padding: CLAUDE.md documents that `terraform validate` evaluates
# file(), so an ungated file() here would make validation fail on any machine
# without the keypair — including the CI runner, which is exactly where the
# verification gate needs to run.
resource "azurerm_key_vault_secret" "ssh_private_key" {
  count = fileexists(pathexpand(var.ssh_private_key_path)) ? 1 : 0

  name         = "vm-ssh-private-key"
  value        = file(pathexpand(var.ssh_private_key_path))
  key_vault_id = azurerm_key_vault.main.id

  depends_on = [azurerm_key_vault_access_policy.terraform]
}

resource "azurerm_key_vault_secret" "ssh_public_key" {
  count = fileexists(pathexpand(var.ssh_public_key_path)) ? 1 : 0

  name         = "vm-ssh-public-key"
  value        = file(pathexpand(var.ssh_public_key_path))
  key_vault_id = azurerm_key_vault.main.id

  depends_on = [azurerm_key_vault_access_policy.terraform]
}

# -----------------------------------------------------------------------------
# Disk Encryption Sets — SSE with customer-managed keys
# -----------------------------------------------------------------------------
# THE CHICKEN-AND-EGG THIS SOLVES
#
# A DES gets a system-assigned identity, and that identity needs wrap/unwrap on
# the Key Vault key before it can encrypt anything. But the identity does not
# exist until the DES exists. Azure permits creating a DES in a non-functional
# state, which is what win-encrypted-disks.sh:66-89 relies on: create the DES,
# read back identity.principalId, then grant it.
#
# The Terraform chain, in order:
#   key.disk_encryption   ->  disk_encryption_set  ->  time_sleep  ->
#   access_policy         ->  managed_disk (depends_on, in compute.tf)
#
# The time_sleep is not superstition. Azure AD replication means a freshly-minted
# service principal is not immediately visible to the Key Vault data plane, so a
# policy written against it can 400 with "principal not found".
#
# key_vault_key_id uses the VERSIONED key id (.id, not .versionless_id), matching
# the script's `az keyvault key show --query key.kid`. A versionless id is only
# valid together with auto_key_rotation_enabled = true.

# One regional DES shared by BOTH Windows nodes, matching the scripts —
# win-encrypted-disks-2.sh re-creates the same winsql-des-* name rather than a
# second set, because a DES is a regional resource and both nodes are in one region.
resource "azurerm_disk_encryption_set" "win" {
  name                = local.win_des_name
  location            = var.location
  resource_group_name = var.resource_group_name
  key_vault_key_id    = azurerm_key_vault_key.disk_encryption.id

  identity {
    type = "SystemAssigned"
  }

  tags = var.tags
}

resource "time_sleep" "wait_for_win_des_identity" {
  create_duration = var.identity_propagation_delay

  triggers = {
    des_id = azurerm_disk_encryption_set.win.id
  }
}

resource "azurerm_key_vault_access_policy" "win_des" {
  key_vault_id = azurerm_key_vault.main.id
  tenant_id    = azurerm_disk_encryption_set.win.identity[0].tenant_id
  object_id    = azurerm_disk_encryption_set.win.identity[0].principal_id

  # TitleCase here; camelCase in key_opts above. See the header note.
  key_permissions = ["Get", "WrapKey", "UnwrapKey"]

  depends_on = [time_sleep.wait_for_win_des_identity]
}

# Separate DES for the Linux workload (encrypted-mgd-disks.sh:22-27). It wraps the
# same Key Vault key but is a distinct set, so the Linux and Windows workloads can
# have their disk encryption revoked independently.
resource "azurerm_disk_encryption_set" "linux" {
  count = var.enable_linux_vm ? 1 : 0

  name                = local.linux_des_name
  location            = var.location
  resource_group_name = var.resource_group_name
  key_vault_key_id    = azurerm_key_vault_key.disk_encryption.id

  identity {
    type = "SystemAssigned"
  }

  tags = var.tags
}

resource "time_sleep" "wait_for_linux_des_identity" {
  count = var.enable_linux_vm ? 1 : 0

  create_duration = var.identity_propagation_delay

  triggers = {
    des_id = azurerm_disk_encryption_set.linux[0].id
  }
}

resource "azurerm_key_vault_access_policy" "linux_des" {
  count = var.enable_linux_vm ? 1 : 0

  key_vault_id = azurerm_key_vault.main.id
  tenant_id    = azurerm_disk_encryption_set.linux[0].identity[0].tenant_id
  object_id    = azurerm_disk_encryption_set.linux[0].identity[0].principal_id

  key_permissions = ["Get", "WrapKey", "UnwrapKey"]

  depends_on = [time_sleep.wait_for_linux_des_identity]
}

# -----------------------------------------------------------------------------
# Linux VM managed identity access — app-vm.sh:223-237
# -----------------------------------------------------------------------------
# The RHEL workload reads secrets and wraps keys directly, which is how the .NET
# workload simulator authenticates to Azure SQL and Always Encrypted without any
# credential on disk.
resource "time_sleep" "wait_for_linux_vm_identity" {
  count = var.enable_linux_vm ? 1 : 0

  create_duration = var.identity_propagation_delay

  triggers = {
    vm_id = azurerm_linux_virtual_machine.app[0].id
  }
}

resource "azurerm_key_vault_access_policy" "linux_vm" {
  count = var.enable_linux_vm ? 1 : 0

  key_vault_id = azurerm_key_vault.main.id
  tenant_id    = azurerm_linux_virtual_machine.app[0].identity[0].tenant_id
  object_id    = azurerm_linux_virtual_machine.app[0].identity[0].principal_id

  secret_permissions = ["Get", "List"]
  key_permissions    = ["Get", "List", "WrapKey", "UnwrapKey"]

  depends_on = [time_sleep.wait_for_linux_vm_identity]
}
