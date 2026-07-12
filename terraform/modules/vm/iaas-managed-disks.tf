# =====================================================
# IaaS SQL-on-VM track — managed disks + attachments (shell parity)
# -----------------------------------------------------
# Sources: win-encrypted-disks.sh / win-encrypted-disks-2.sh (SQL nodes,
# SSE-CMK via winsql-des), encrypted-mgd-disks.sh + app-vm.sh (Linux, via
# sql-des), dc-vm.sh (DC disks, platform-encrypted). Caching follows the
# SQL-Server-on-Azure-VM guidance the scripts encode: data/tempdb ReadOnly,
# log/backup None; AD DS disks None.
#
# ZONE vs ZRS — recorded deviation from the scripts' flags: the disk scripts
# pass BOTH `--zone <n>` and `--sku StandardSSD_ZRS`, but per Microsoft docs a
# ZRS managed disk is zone-REDUNDANT and cannot be zonal (zonal disks are LRS
# only; learn.microsoft.com/azure/virtual-machines/disks-redundancy). The only
# state Azure can hold for the committed SKU is ZRS with no zone — declared
# here directly. ZRS disks attach to the zonal VMs in any zone, so the
# cross-zone attach the scripts rely on still works. If the SKU is ever
# switched to an LRS type, add zonal pinning back (disk zone must then equal
# its VM's zone).
# =====================================================

locals {
  # --- Windows SQL node disks (sizes from env.conf:251-254, LUNs/caching from
  #     win-encrypted-disks*.sh:158-167) ---
  iaas_win_node_disks = {
    "node1-data"   = { name = "winsql-data-dsk-${local.iaas_vm_sfx}", size = 4022, lun = 0, caching = "ReadOnly", vm = "node1" }
    "node1-log"    = { name = "winsql-log-dsk-${local.iaas_vm_sfx}", size = 2011, lun = 1, caching = "None", vm = "node1" }
    "node1-tempdb" = { name = "winsql-tempdb-dsk-${local.iaas_vm_sfx}", size = 1024, lun = 2, caching = "ReadOnly", vm = "node1" }
    "node1-backup" = { name = "winsql-backup-dsk-${local.iaas_vm_sfx}", size = 8124, lun = 3, caching = "None", vm = "node1" }

    "node2-data"   = { name = "winsql-data-dsk2-${local.iaas_vm_sfx}", size = 4022, lun = 0, caching = "ReadOnly", vm = "node2" }
    "node2-log"    = { name = "winsql-log-dsk2-${local.iaas_vm_sfx}", size = 2011, lun = 1, caching = "None", vm = "node2" }
    "node2-tempdb" = { name = "winsql-tempdb-dsk2-${local.iaas_vm_sfx}", size = 1024, lun = 2, caching = "ReadOnly", vm = "node2" }
    "node2-backup" = { name = "winsql-backup-dsk2-${local.iaas_vm_sfx}", size = 8124, lun = 3, caching = "None", vm = "node2" }
  }

  # --- Linux workload disks (encrypted-mgd-disks.sh:46-78, attach order/
  #     caching from app-vm.sh:70-173) ---
  iaas_linux_disks = {
    "data"   = { name = "data-dsk-${local.iaas_vm_sfx}", size = 4028, lun = 0 }
    "log"    = { name = "log-dsk-${local.iaas_vm_sfx}", size = 2048, lun = 1 }
    "temp"   = { name = "temp-dsk-${local.iaas_vm_sfx}", size = 1024, lun = 2 }
    "backup" = { name = "backup-dsk-${local.iaas_vm_sfx}", size = 4096, lun = 3 }
  }
}

# =====================================================
# Windows SQL node disks — SSE-CMK via winsql-des
# =====================================================

resource "azurerm_managed_disk" "iaas_win_node" {
  for_each = var.iaas_enabled ? local.iaas_win_node_disks : {}

  name                   = each.value.name
  location               = var.iaas_location
  resource_group_name    = var.iaas_rg
  storage_account_type   = var.iaas_win_disk_sku
  disk_size_gb           = each.value.size
  create_option          = "Empty"
  disk_encryption_set_id = var.iaas_windows_des_id
}

resource "azurerm_virtual_machine_data_disk_attachment" "iaas_win_node" {
  for_each = var.iaas_enabled ? local.iaas_win_node_disks : {}

  managed_disk_id = azurerm_managed_disk.iaas_win_node[each.key].id
  virtual_machine_id = (
    each.value.vm == "node1"
    ? azurerm_windows_virtual_machine.iaas_sql_node1[0].id
    : azurerm_windows_virtual_machine.iaas_sql_node2[0].id
  )
  lun     = each.value.lun
  caching = each.value.caching
}

# =====================================================
# Linux workload disks — SSE-CMK via sql-des (caching None on all four)
# =====================================================

resource "azurerm_managed_disk" "iaas_linux" {
  for_each = var.iaas_enabled ? local.iaas_linux_disks : {}

  name                   = each.value.name
  location               = var.iaas_location
  resource_group_name    = var.iaas_rg
  storage_account_type   = "StandardSSD_ZRS"
  disk_size_gb           = each.value.size
  create_option          = "Empty"
  disk_encryption_set_id = var.iaas_linux_des_id
}

resource "azurerm_virtual_machine_data_disk_attachment" "iaas_linux" {
  for_each = var.iaas_enabled ? local.iaas_linux_disks : {}

  managed_disk_id    = azurerm_managed_disk.iaas_linux[each.key].id
  virtual_machine_id = azurerm_linux_virtual_machine.iaas_linux[0].id
  lun                = each.value.lun
  caching            = "None"
}

# =====================================================
# Domain controller disks — AD DS database/logs (dc-vm.sh:97/:146),
# platform-managed encryption (the shell passes no DES), caching None per
# AD DS guidance, LUN 0 (az vm disk attach without --lun picks the first
# free LUN on a fresh VM).
# =====================================================

resource "azurerm_managed_disk" "iaas_dc" {
  count = var.iaas_enabled ? 1 : 0

  name                 = "DC-MGD-DSK"
  location             = var.iaas_location
  resource_group_name  = var.iaas_rg
  storage_account_type = var.iaas_win_disk_sku
  disk_size_gb         = 4098
  create_option        = "Empty"
}

resource "azurerm_virtual_machine_data_disk_attachment" "iaas_dc" {
  count = var.iaas_enabled ? 1 : 0

  managed_disk_id    = azurerm_managed_disk.iaas_dc[0].id
  virtual_machine_id = azurerm_windows_virtual_machine.iaas_dc[0].id
  lun                = 0
  caching            = "None"
}

resource "azurerm_managed_disk" "iaas_dc2" {
  count = var.iaas_enabled ? 1 : 0

  name                 = "DC2-MGD-DSK"
  location             = var.iaas_location
  resource_group_name  = var.iaas_rg
  storage_account_type = var.iaas_win_disk_sku
  disk_size_gb         = 4098
  create_option        = "Empty"
}

resource "azurerm_virtual_machine_data_disk_attachment" "iaas_dc2" {
  count = var.iaas_enabled ? 1 : 0

  managed_disk_id    = azurerm_managed_disk.iaas_dc2[0].id
  virtual_machine_id = azurerm_windows_virtual_machine.iaas_dc2[0].id
  lun                = 0
  caching            = "None"
}
