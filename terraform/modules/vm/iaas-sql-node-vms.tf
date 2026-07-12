# =====================================================
# IaaS SQL-on-VM track — Windows SQL Server node VMs
# -----------------------------------------------------
# Mirrors scripts/shell/test-env/win-sql-vm.sh (Node 1, ms-<suffix>, zone 1)
# and win-sql-vm-2.sh (Node 2, cs-<suffix>, zone 2). Base Windows Server 2022
# platform image — SQL Server 2022 Developer + SSMS are installed in-guest by
# ansible/playbooks/sql-server-on-windows.yml (no Marketplace plan/licensing).
# Node sizes are asymmetric in the shell deployment (D8s_v3 / B2ms) — strict
# parity, raise both for real workloads.
# =====================================================

resource "azurerm_windows_virtual_machine" "iaas_sql_node1" {
  count = var.iaas_enabled ? 1 : 0

  name                = "ms-${local.iaas_vm_sfx}"
  location            = var.iaas_location
  resource_group_name = var.iaas_rg
  size                = var.iaas_win_vm_size
  zone                = local.iaas_win_vm_zone

  admin_username = var.iaas_admin_username
  admin_password = var.iaas_admin_password

  network_interface_ids = [var.iaas_win_nic_id]

  identity {
    type = "SystemAssigned"
  }

  os_disk {
    name                 = "winsql-osdisk-${local.iaas_vm_sfx}"
    caching              = "ReadWrite"
    storage_account_type = "StandardSSD_ZRS"
  }

  source_image_reference {
    publisher = "MicrosoftWindowsServer"
    offer     = "WindowsServer"
    sku       = "2022-datacenter-azure-edition"
    version   = "latest"
  }
}

resource "azurerm_windows_virtual_machine" "iaas_sql_node2" {
  count = var.iaas_enabled ? 1 : 0

  name                = "cs-${local.iaas_vm_sfx}"
  location            = var.iaas_location
  resource_group_name = var.iaas_rg
  size                = var.iaas_win_vm_size_2
  zone                = local.iaas_win_vm_zone2

  admin_username = var.iaas_admin_username
  admin_password = var.iaas_admin_password

  network_interface_ids = [var.iaas_win2_nic_id]

  identity {
    type = "SystemAssigned"
  }

  os_disk {
    name                 = "winsql-osdisk2-${local.iaas_vm_sfx}"
    caching              = "ReadWrite"
    storage_account_type = "StandardSSD_ZRS"
  }

  source_image_reference {
    publisher = "MicrosoftWindowsServer"
    offer     = "WindowsServer"
    sku       = "2022-datacenter-azure-edition"
    version   = "latest"
  }
}

resource "azurerm_virtual_machine_run_command" "iaas_sql_node1_winrm" {
  count = var.iaas_enabled ? 1 : 0

  name               = "enable-winrm"
  location           = var.iaas_location
  virtual_machine_id = azurerm_windows_virtual_machine.iaas_sql_node1[0].id

  source {
    script = local.iaas_winrm_script
  }
}

resource "azurerm_virtual_machine_run_command" "iaas_sql_node2_winrm" {
  count = var.iaas_enabled ? 1 : 0

  name               = "enable-winrm"
  location           = var.iaas_location
  virtual_machine_id = azurerm_windows_virtual_machine.iaas_sql_node2[0].id

  source {
    script = local.iaas_winrm_script
  }
}
