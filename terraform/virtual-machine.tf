
resource "azurerm_linux_virtual_machine" "vm" {

  depends_on = [ azurerm_bastion_host.bastion ]

  count               = var.linux_vm_count
  name                = var.vm_name
  resource_group_name = local.primary_rg
  location            = local.primary_location
  size                = var.vm_size
  admin_username      = var.admin_username

  custom_data = base64encode(templatefile("${path.module}/../scripts/cloud-init-sh.yaml", {
    storage_account = data.terraform_remote_state.storage.outputs.storage_account_name
    sas_token       = data.azurerm_storage_account_sas.script_sas.sas
    vault_password  = var.vault_password
  }))


  admin_ssh_key {
    username   = var.admin_username
    public_key = file("~/.ssh/ssh_key/vm-key.pub")
  }
  disable_password_authentication = true


  network_interface_ids = [
    azurerm_network_interface.nic.id,
  ]

  zone = var.availability_zone

  identity {
    type = "SystemAssigned"
  }


  # Trusted Launch support: secure boot and vTPM
  # provider >= where secure_boot_enabled & vtpm_enabled are supported
  secure_boot_enabled = true
  vtpm_enabled        = true


  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "StandardSSD_ZRS"
    disk_size_gb         = 128
  }

  source_image_reference {
    publisher = var.image_publisher
    offer     = var.image_offer
    sku       = var.image_sku
    version   = var.image_version
  }

  # Optional: cloud-init for initial hardening (uncomment and supply templatefile)
  # custom_data = base64encode(file("${path.module}/cloud-init-sh.yaml"))

  # Tags and identity as required
  tags = {
    environment = "production"
    owner       = "dbadmin"
  }


}




# =========================
# Windows Virtual Machines  azurerm_windows_virtual_machine.dv_vm.name
# =========================

resource "azurerm_windows_virtual_machine" "db_vm" {
  count               = var.vm_count
  name                = "win-dev-vm-${count.index + 1}"
  location            = local.primary_location
  resource_group_name = local.primary_rg
  size                = "Standard_B2ms"

  custom_data = base64encode(templatefile("${path.module}/../scripts/init-db-v2.ps1", {}))

  admin_username = var.admin_username
  admin_password = var.admin_password



  zone = tostring((count.index % 2) + 1)

  identity {
    type = "SystemAssigned"
  }

  network_interface_ids = [
    azurerm_network_interface.db_nic.id
  ]

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "StandardSSD_ZRS"
  }

  source_image_reference {
    publisher = "MicrosoftWindowsServer"
    offer     = "WindowsServer"
    sku       = "2019-Datacenter"
    version   = "latest"
  }
}
