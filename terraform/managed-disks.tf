

# ==============
# Managed Disks
# ==============

resource "azurerm_managed_disk" "db_data_disk" {
  count                = local.win_data_disk_count
  name                 = "disk-db-data-${count.index + 1}"
  location             = local.primary_location
  resource_group_name  = local.primary_rg
  storage_account_type = "StandardSSD_ZRS"
  disk_size_gb         = 1024
  create_option        = "Empty"
}

resource "azurerm_managed_disk" "db_log_disk" {
  count                = local.win_log_disk_count
  name                 = "disk-db-log-${count.index + 1}"
  location             = local.primary_location
  resource_group_name  = local.primary_rg
  storage_account_type = "StandardSSD_ZRS"
  disk_size_gb         = 512
  create_option        = "Empty"
}

# =================
# Disk Attachments
# =================

resource "azurerm_virtual_machine_data_disk_attachment" "db_data_attach" {
  count = local.win_data_disk_count

  managed_disk_id = azurerm_managed_disk.db_data_disk[count.index].id

  virtual_machine_id = azurerm_windows_virtual_machine.db_vm[
    floor(count.index / var.data_disks_per_vm)
  ].id

  lun     = (count.index % var.data_disks_per_vm) + local.data_lun_start
  caching = "ReadOnly"
}



resource "azurerm_virtual_machine_data_disk_attachment" "db_log_attach" {
  count = local.win_log_disk_count

  managed_disk_id = azurerm_managed_disk.db_log_disk[count.index].id

  virtual_machine_id = azurerm_windows_virtual_machine.db_vm[
    floor(count.index / var.log_disks_per_vm)
  ].id

  lun     = (count.index % var.log_disks_per_vm) + local.log_lun_start
  caching = "None"
}






# ==============
# Managed Disks
# ==============

resource "azurerm_managed_disk" "linux_db_data_disk" {
  count                = local.lin_data_disk_count
  name                 = "lin-disk-db-data-${count.index + 1}"
  location             = local.primary_location
  resource_group_name  = local.primary_rg
  storage_account_type = "StandardSSD_ZRS"
  disk_size_gb         = 1024
  create_option        = "Empty"
}

resource "azurerm_managed_disk" "linux_db_log_disk" {
  count                = local.lin_data_disk_count
  name                 = "lin-disk-db-log-${count.index + 1}"
  location             = local.primary_location
  resource_group_name  = local.primary_rg
  storage_account_type = "StandardSSD_ZRS"
  disk_size_gb         = 512
  create_option        = "Empty"
}

# =================
# Disk Attachments
# =================

resource "azurerm_virtual_machine_data_disk_attachment" "linux_db_data_attach" {

  depends_on = [azurerm_linux_virtual_machine.vm]

  count = local.lin_data_disk_count

  managed_disk_id = azurerm_managed_disk.linux_db_data_disk[count.index].id

  virtual_machine_id = azurerm_linux_virtual_machine.vm[
    floor(count.index / var.data_disks_per_linux_vm)
  ].id

  lun     = (count.index % var.data_disks_per_linux_vm) + local.data_lun_start
  caching = "ReadOnly"
}



resource "azurerm_virtual_machine_data_disk_attachment" "linux_db_log_attach" {

  depends_on = [azurerm_linux_virtual_machine.vm]
  count      = local.lin_data_disk_count

  managed_disk_id = azurerm_managed_disk.linux_db_log_disk[count.index].id

  virtual_machine_id = azurerm_linux_virtual_machine.vm[
    floor(count.index / var.log_disks_per_linux_vm)
  ].id

  lun     = (count.index % var.log_disks_per_linux_vm) + local.log_lun_start
  caching = "None"
}

