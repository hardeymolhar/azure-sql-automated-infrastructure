
resource "azurerm_storage_account" "bootstrap" {
  name                     = local.storage_account_name
  resource_group_name      = var.resource_group_name
  location                 = var.location
  account_kind             = "StorageV2"
  account_tier             = "Standard"
  account_replication_type = "ZRS" # Upgrade from LRS

  min_tls_version                 = "TLS1_2"
  allow_nested_items_to_be_public = false
  shared_access_key_enabled       = true # 🔥 critical

  blob_properties {
    versioning_enabled = true

    delete_retention_policy {
      days = 30
    }

    container_delete_retention_policy {
      days = 30
    }
  }

  network_rules {
    default_action = "Allow"

    ip_rules = [
      "${local.client_ip}/30"
    ]

    bypass = ["AzureServices"]
  }
}

resource "azurerm_storage_container" "containers" {
  for_each              = toset(["terraform-state-files", "lab-resources", "xevents", "backups"])
  name                  = each.key
  storage_account_id    = azurerm_storage_account.bootstrap.id
  container_access_type = "private"
}



resource "azurerm_storage_blob" "scripts" {
  for_each = fileset("${path.module}/../../scripts", "*")

  name                   = each.value
  storage_account_name   = azurerm_storage_account.bootstrap.name
  storage_container_name = azurerm_storage_container.containers["lab-resources"].name
  type                   = "Block"

  source = "${path.module}/../../scripts/${each.value}"
}

# -----------------------------------------------------------------------------
# The DP-300 lab archive
# -----------------------------------------------------------------------------
# Replaces vm-config.sh's `az storage blob upload`. This is the object the SAS in
# data.tf is minted for and the one both Ansible plays download.
#
# It lives HERE, not in terraform_flat/, because this root owns the storage account
# and the container. Declaring it upstream would mean the flat root writing into a
# data plane it does not own, and would need the container id threaded back out
# through remote state just to upload one file.
#
# count, not a feature flag: docs/lab-files/ is gitignored (~119 MB), so a checkout
# without it must plan to zero resources rather than fail on a missing `source`.
#
# storage_account_name + storage_container_name rather than storage_container_id:
# the latter does not exist in azurerm 4.75.0, which versions.tf pins. See the note
# there for why this root moved back off 5.0.1.
resource "azurerm_storage_blob" "lab_archive" {
  count = local.lab_archive_available ? 1 : 0

  name                   = local.lab_blob_name
  storage_account_name   = azurerm_storage_account.bootstrap.name
  storage_container_name = azurerm_storage_container.containers["lab-resources"].name
  type                   = "Block"

  source = var.lab_archive_path
}



/* 
| Component   | Role                                                                 |
| ----------- | -------------------------------------------------------------------- |
| `fileset()` | discovers files and returns **relative paths** (not full paths)      |
| `for_each`  | iterates over each discovered file  returned by 'fileset()'          |
| `source`    | provides the **full file path** so Terraform can locate and read it  |

Key Concepts:
- A file in Terraform is accessed via its **path (location on disk)**, not just its name.
- `fileset()` returns paths **relative to the base directory used for discovery**.
- It does NOT retain or expose that base directory after returning results.

Why `source` is required:
- Terraform needs a **complete path** to locate and read a file.
- Relative paths like "install.sh" are ambiguous without a base directory.
- Terraform does NOT assume or remember the working directory used in `fileset()`.

What `source` does:
- Reconstructs the full path:
  `${path.module}/scripts/${each.value}`
- Ensures Terraform can reliably access the file regardless of execution context (local, CI/CD, modules).

Without `source`:
- Terraform only sees relative paths (e.g. "install.sh")
- It attempts to resolve them from the current working directory
- This results in file not found errors

Conclusion:
- `fileset()` = file discovery (relative paths)
- `source` = file resolution (absolute/full path)
- Both are required because Terraform separates **what files exist** from **where they are located**
*/