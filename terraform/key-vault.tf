/*

STEPS TO SWITCHING TDE PROTECTOR FROM MICROSOFT MANAGED KEY (MMK) TO KEY VAULT KEY (CMK)

1. Enable Managed Identity on SQL Server
2. Create Key Vault
3. Create Key Vault Key (with key_opts)
4. Grant SQL Server's system assigned identity access to Key Vault
   by creating an access policy with "Get", "WrapKey", and "UnwrapKey" permissions
5. Configure SQL Server to use the key (TDE protector)
*/


/* SETUP PHASE

1. SQL Creates DEK
2. SQL Calls Key Vault to wrap DEK with the specified key (sql_key)
3. Key Vault returns the wrapped DEK to SQL
4. SQL stores the wrapped DEK and uses it for encrypting data at rest

   RUNTIME PHASE

1. When SQL needs to read/write data, it retrieves the wrapped DEK from storage
2. SQL calls Key Vault to unwrap the DEK using the same key (sql_key)
3. Key Vault returns the unwrapped DEK to SQL
*/

resource "azurerm_key_vault" "kv" {
  name                = "kv-${random_string.suffix.result}"
  location            = local.primary_location
  resource_group_name = local.primary_rg
  tenant_id           = data.azurerm_client_config.current.tenant_id
  sku_name            = "standard"

  soft_delete_retention_days = 7
  purge_protection_enabled   = true

  public_network_access_enabled = true
  network_acls {
    default_action = "Allow"

    ip_rules = ["${local.client_ip}"]
    bypass   = "AzureServices"
  }

  enabled_for_deployment          = true # Allows VMs to pull secrets during provisioning
  enabled_for_template_deployment = true # Allows ARM templates to access Key Vault
  enabled_for_disk_encryption     = true # Allows Azure Disk Encryption to access Key Vault for encrypting VM disks
}

resource "azurerm_key_vault_access_policy" "sql_policy" {
  key_vault_id = azurerm_key_vault.kv.id
  tenant_id    = azurerm_mssql_server.sql.identity[0].tenant_id
  object_id    = azurerm_mssql_server.sql.identity[0].principal_id

  key_permissions = [
    "Get",
    "WrapKey",
    "UnwrapKey"
  ]
  depends_on = [
    azurerm_mssql_server.sql
  ]
}

resource "azurerm_key_vault_access_policy" "sql_secondary_policy" {
  key_vault_id = azurerm_key_vault.kv.id
  tenant_id    = azurerm_mssql_server.sql_secondary.identity[0].tenant_id
  object_id    = azurerm_mssql_server.sql_secondary.identity[0].principal_id

  key_permissions = [
    "Get",
    "WrapKey",
    "UnwrapKey"
  ]
  depends_on = [
    azurerm_mssql_server.sql_secondary
  ]
}


resource "azurerm_key_vault_access_policy" "terraform_policy" {
  key_vault_id = azurerm_key_vault.kv.id
  tenant_id    = data.azurerm_client_config.current.tenant_id
  object_id    = data.azurerm_client_config.current.object_id

  key_permissions = [
    "Get",
    "List",
    "Create",
    "Update",
    "Delete",
    "Recover",
    "Backup",
    "Restore",

    "WrapKey",
    "UnwrapKey",
    "Encrypt",
    "Decrypt",
    "Sign",
    "Verify",

    "Purge",
    "Release",

    "Rotate",
    "GetRotationPolicy",
    "SetRotationPolicy"
  ]

  secret_permissions      = ["Get", "List", "Set", "Delete", "Recover", "Backup", "Restore", "Purge"]
  certificate_permissions = ["Get", "List", "Create", "Update", "Delete", "Recover", "Backup", "Restore", "Purge"]
}

resource "azurerm_key_vault_key" "sql_key" {
  name         = "sql-tde-key"
  key_vault_id = azurerm_key_vault.kv.id
  key_type     = "RSA"
  key_size     = 2048

  key_opts = ["wrapKey", "unwrapKey"]

  rotation_policy {
    automatic {
      time_before_expiry = "P30D"
    }

    expire_after         = "P90D"
    notify_before_expiry = "P15D"
  }
  depends_on = [
    azurerm_key_vault_access_policy.terraform_policy
  ]
}

resource "azurerm_key_vault_secret" "ssh_private_key" {
  name         = "vm-ssh-private-key"
  value        = file("~/.ssh/ssh_key/vm-key")
  key_vault_id = azurerm_key_vault.kv.id
}


/*  IT DOES THE FOLLOWING:
1. Creates a TDE protector on the SQL Server using the Key Vault Key
2. This automatically enables TDE on all databases under the server
3. During failover, the secondary server will use the same key for TDE since it's referencing the same Key Vault Key ID

NOTE: Azure SQL Database automatically encrypts data at rest with a Microsoft-managed key if you don't configure TDE with your own key.
By configuring TDE with your own key, you can have control over the encryption keys and manage them in Azure Key Vault.
This is often referred to as "Bring Your Own Key" (BYOK) for TDE.
*/

resource "azurerm_mssql_server_transparent_data_encryption" "tde_key" {
  server_id        = azurerm_mssql_server.sql.id
  key_vault_key_id = azurerm_key_vault_key.sql_key.id

  depends_on = [
    azurerm_key_vault_key.sql_key,
    azurerm_key_vault_access_policy.sql_policy,
    azurerm_key_vault_access_policy.sql_secondary_policy
  ]
}


resource "azurerm_mssql_server_transparent_data_encryption" "tde_key_secondary" {
  server_id        = azurerm_mssql_server.sql_secondary.id
  key_vault_key_id = azurerm_key_vault_key.sql_key.id

  depends_on = [
    azurerm_key_vault_key.sql_key,
    azurerm_key_vault_access_policy.sql_policy,
    azurerm_key_vault_access_policy.sql_secondary_policy
  ]
}







