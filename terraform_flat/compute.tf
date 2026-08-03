# =============================================================================
# COMPUTE — replaces win-sql-vm.sh, win-sql-vm-2.sh, win-encrypted-disks.sh,
#           win-encrypted-disks-2.sh, encrypted-mgd-disks.sh and app-vm.sh
# -----------------------------------------------------------------------------
# db-deploy.sh STEPs 5-10.
#
# The shell pipeline had two OPPOSITE ordering rules here, and got them right only
# by careful comment discipline (db-deploy.sh:55-72):
#   * Linux  — "disks first, then VM": encrypted-mgd-disks.sh created the disks,
#              app-vm.sh created the VM and attached them.
#   * Windows — "VM first, then disks": win-sql-vm*.sh created the VM,
#              win-encrypted-disks*.sh created the disks and attached them.
#
# In Terraform that distinction evaporates. azurerm_virtual_machine_data_disk_attachment
# is a resource in its own right that references both sides, so disks and VMs are
# simply two independent nodes with the attachment depending on each. There is no
# ordering rule left to remember or to get wrong.
#
# HA SHAPE: node 1 in availability zone 1, node 2 in zone 2, so a single-zone
# outage cannot take both replicas of the availability group. Each node's data
# disks are pinned to the SAME zone as the VM, because a zonal disk cannot attach
# to a VM in another zone.
# =============================================================================

# -----------------------------------------------------------------------------
# Windows SQL Server nodes
# -----------------------------------------------------------------------------
# The image is a BASE Windows Server 2022 platform image, not a SQL Server
# marketplace image. That is deliberate: marketplace SQL images require plan
# acceptance the sandbox subscription cannot perform. SQL Server 2022 Developer
# and SSMS are installed afterwards by ansible/playbooks/sql-server-on-windows.yml.
resource "azurerm_windows_virtual_machine" "sql" {
  for_each = local.win_nodes

  name                = each.value.name
  computer_name       = each.value.name
  resource_group_name = var.resource_group_name
  location            = var.location
  size                = each.value.size
  zone                = each.value.zone

  admin_username = var.admin_username
  admin_password = var.admin_password

  network_interface_ids = [azurerm_network_interface.win[each.key].id]

  # System-assigned identity, matching `az vm create --assign-identity` with no
  # value. Gives each node an Entra identity it can use to reach Key Vault and
  # storage without a credential on disk.
  identity {
    type = "SystemAssigned"
  }

  os_disk {
    name                 = each.value.os_disk_name
    caching              = "ReadWrite"
    storage_account_type = var.win_os_disk_type
  }

  source_image_reference {
    publisher = var.win_image.publisher
    offer     = var.win_image.offer
    sku       = var.win_image.sku
    version   = var.win_image.version
  }

  tags = var.tags

  # Private DNS must be linked and accepting registrations BEFORE the nodes boot,
  # or they miss their auto-registration window and WSFC has nothing to resolve.
  # private-dns.sh:23-24 states this requirement; here it is enforced.
  depends_on = [
    azurerm_private_dns_zone_virtual_network_link.corp,
    azurerm_network_interface_security_group_association.win,
  ]
}

# -----------------------------------------------------------------------------
# WinRM bootstrap — win-sql-vm.sh:83-100 and win-sql-vm-2.sh:73-90
# -----------------------------------------------------------------------------
# Ansible manages Windows over WinRM, and a stock Windows Server image will not
# accept an Ansible connection: the HTTPS listener does not exist, and
# Enable-PSRemoting's own firewall rule is scoped to the local subnet only. The
# 13-line script in locals.tf fixes both. See locals.tf for why each line is
# ordered the way it is.
#
# WHY azurerm_virtual_machine_run_command AND NOT azurerm_virtual_machine_extension:
#   The modular root uses a CustomScriptExtension (terraform/modules/vm/main.tf:128).
#   Two concrete problems with that here. First, a failed extension leaves the VM
#   in a Failed provisioning state that blocks every subsequent apply until it is
#   manually removed. Second, it forces all 13 statements into a single
#   commandToExecute JSON string, which means escaping PowerShell inside JSON
#   inside HCL. A run command takes the script as a plain heredoc.
#
# BEHAVIOURAL DIFFERENCE from the shell pipeline, worth knowing: `az vm run-command
# invoke` was a transient action that re-ran on every db-deploy.sh pass. This is a
# persistent child resource that re-executes only when the script changes or the VM
# is replaced. That is better — the script's unconditional re-run was wasteful — but
# it means if WinRM breaks in-guest for an unrelated reason, `terraform apply` will
# not silently re-fix it. Force a re-run with:
#   terraform apply -replace='azurerm_virtual_machine_run_command.winrm["node1"]'
resource "azurerm_virtual_machine_run_command" "winrm" {
  for_each = local.win_nodes

  name               = "enable-winrm"
  location           = var.location
  virtual_machine_id = azurerm_windows_virtual_machine.sql[each.key].id

  source {
    script = local.winrm_bootstrap_script
  }

  tags = var.tags
}

# -----------------------------------------------------------------------------
# Windows SQL data disks — win-encrypted-disks*.sh
# -----------------------------------------------------------------------------
# Eight disks from one block (2 nodes x 4 roles), encrypted at rest with the
# customer-managed key via the shared Disk Encryption Set.
#
# StandardSSD_LRS rather than ZRS: these disks are ZONAL (pinned to their VM's
# zone), and zone-redundant storage is not applicable to a zonal disk.
resource "azurerm_managed_disk" "win" {
  for_each = local.win_disks

  name                = each.value.name
  location            = var.location
  resource_group_name = var.resource_group_name
  zone                = each.value.zone

  storage_account_type = var.win_data_disk_sku
  create_option        = "Empty"
  disk_size_gb         = each.value.size

  # SSE with a customer-managed key. The estate owns the key that protects its own
  # data at rest, rather than relying on Microsoft-managed platform keys.
  disk_encryption_set_id = azurerm_disk_encryption_set.win.id

  tags = var.tags

  # NOT redundant with the disk_encryption_set_id reference above. That reference
  # only guarantees the DES exists — not that the DES's identity has been granted
  # wrap/unwrap on the key. Without this edge, Terraform may create a disk while
  # the DES is still unable to wrap, which fails with KeyVaultAccessForbidden.
  depends_on = [azurerm_key_vault_access_policy.win_des]
}

# Caching is a performance decision, not a default. Data and tempdb take ReadOnly
# host caching because their access pattern is read-heavy and the host cache is a
# genuine win. Log and backup disks take None, because write-ahead-log durability
# must never be buffered by a host cache the storage layer cannot flush on demand.
resource "azurerm_virtual_machine_data_disk_attachment" "win" {
  for_each = local.win_disks

  managed_disk_id    = azurerm_managed_disk.win[each.key].id
  virtual_machine_id = azurerm_windows_virtual_machine.sql[each.value.node].id
  lun                = each.value.lun
  caching            = each.value.caching
}

# =============================================================================
# LINUX APPLICATION VM — gated on var.enable_linux_vm (default false)
# -----------------------------------------------------------------------------
# encrypted-mgd-disks.sh (STEP 5) and app-vm.sh (STEP 6), both commented out in
# db-deploy.sh. app-vm.sh additionally cannot run as written: app-vm.sh:28 calls a
# `resource_exists` function that is defined nowhere in the repo, so under
# `set -euo pipefail` it exits 127 immediately. Converting it to Terraform fixes
# that by construction — there is no hand-rolled existence guard to get wrong,
# because state is the existence guard.
# =============================================================================

resource "azurerm_linux_virtual_machine" "app" {
  count = var.enable_linux_vm ? 1 : 0

  name                = local.linux_vm_name
  computer_name       = local.linux_vm_name
  resource_group_name = var.resource_group_name
  location            = var.location
  size                = var.linux_vm_size

  admin_username                  = var.admin_username
  disable_password_authentication = true

  admin_ssh_key {
    username   = var.admin_username
    public_key = file(pathexpand(var.ssh_public_key_path))
  }

  network_interface_ids = [azurerm_network_interface.linux[0].id]

  identity {
    type = "SystemAssigned"
  }

  os_disk {
    name                 = local.linux_os_disk_name
    caching              = "ReadWrite"
    storage_account_type = "StandardSSD_LRS"
    disk_size_gb         = var.linux_os_disk_size_gb
  }

  source_image_reference {
    publisher = var.linux_image.publisher
    offer     = var.linux_image.offer
    sku       = var.linux_image.sku
    version   = var.linux_image.version
  }

  tags = var.tags

  depends_on = [azurerm_network_interface_security_group_association.linux]
}

# Deliberately different from the Windows disks and preserved as the script had
# them: ZRS instead of LRS, and NON-zonal (no zone argument). The Linux VM is not
# zone-pinned, so its disks must not be either — a zonal disk could not attach.
resource "azurerm_managed_disk" "linux" {
  for_each = var.enable_linux_vm ? local.linux_disks : {}

  name                = each.value.name
  location            = var.location
  resource_group_name = var.resource_group_name

  storage_account_type = var.linux_disk_sku
  create_option        = "Empty"
  disk_size_gb         = each.value.size

  disk_encryption_set_id = azurerm_disk_encryption_set.linux[0].id

  tags = var.tags

  depends_on = [azurerm_key_vault_access_policy.linux_des]
}

# All four Linux disks use caching = "None", matching app-vm.sh:70-170. The Linux
# SQL Server layout mounts these as /u02-/u05 via
# ansible/playbooks/dbdrive-configuration.yml.
resource "azurerm_virtual_machine_data_disk_attachment" "linux" {
  for_each = var.enable_linux_vm ? local.linux_disks : {}

  managed_disk_id    = azurerm_managed_disk.linux[each.key].id
  virtual_machine_id = azurerm_linux_virtual_machine.app[0].id
  lun                = each.value.lun
  caching            = "None"
}
