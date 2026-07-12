# =====================================================
# IaaS SQL-on-VM track — Active Directory domain controller VMs
# -----------------------------------------------------
# Mirrors scripts/shell/test-env/dc-vm.sh. Terraform only CREATES the VMs and
# bootstraps WinRM; the AD DS role install, forest promotion (sqlfci.local),
# and replica promotion stay in-guest with Ansible
# (configure-domain-controller.yml / configure-dc2.yml).
# dc-<suffix> = zone 1 forest root, dc2-<suffix> = zone 2 replica; both attach
# to the pre-created static-IP DC NICs (10.10.4.4 / 10.10.4.5).
# =====================================================

resource "azurerm_windows_virtual_machine" "iaas_dc" {
  count = var.iaas_enabled ? 1 : 0

  name                = "dc-${local.iaas_vm_sfx}"
  location            = var.iaas_location
  resource_group_name = var.iaas_rg
  size                = var.iaas_dc_vm_size
  zone                = local.iaas_dc_vm_zone

  admin_username = var.iaas_admin_username
  admin_password = var.iaas_admin_password

  network_interface_ids = [var.iaas_dc_nic_id]

  identity {
    type = "SystemAssigned"
  }

  os_disk {
    name                 = "dc-osdisk-${local.iaas_vm_sfx}"
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

resource "azurerm_windows_virtual_machine" "iaas_dc2" {
  count = var.iaas_enabled ? 1 : 0

  name                = "dc2-${local.iaas_vm_sfx}"
  location            = var.iaas_location
  resource_group_name = var.iaas_rg
  size                = var.iaas_dc_vm_size
  zone                = local.iaas_dc2_vm_zone

  admin_username = var.iaas_admin_username
  admin_password = var.iaas_admin_password

  network_interface_ids = [var.iaas_dc2_nic_id]

  identity {
    type = "SystemAssigned"
  }

  os_disk {
    name                 = "dc2-osdisk-${local.iaas_vm_sfx}"
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

resource "azurerm_virtual_machine_run_command" "iaas_dc_winrm" {
  count = var.iaas_enabled ? 1 : 0

  name               = "enable-winrm"
  location           = var.iaas_location
  virtual_machine_id = azurerm_windows_virtual_machine.iaas_dc[0].id

  source {
    script = local.iaas_winrm_script
  }
}

resource "azurerm_virtual_machine_run_command" "iaas_dc2_winrm" {
  count = var.iaas_enabled ? 1 : 0

  name               = "enable-winrm"
  location           = var.iaas_location
  virtual_machine_id = azurerm_windows_virtual_machine.iaas_dc2[0].id

  source {
    script = local.iaas_winrm_script
  }
}
