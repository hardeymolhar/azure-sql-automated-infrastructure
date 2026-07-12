# =====================================================
# IaaS SQL-on-VM track — Linux workload VM (vm-<suffix>)
# -----------------------------------------------------
# Mirrors scripts/shell/test-env/app-vm.sh: RHEL 9, SSH-key-only auth,
# non-zonal (app-vm.sh passes no --zone), 512 GB StandardSSD_LRS OS disk,
# system-assigned managed identity. The MI's Key Vault access policy
# (secrets get/list + keys get/wrap/unwrap/list, app-vm.sh:223/:234) is owned
# here because it lives and dies with the VM identity — placing it in the
# security module would create a security<->vm module cycle.
# =====================================================

resource "azurerm_linux_virtual_machine" "iaas_linux" {
  count = var.iaas_enabled ? 1 : 0

  name                = "vm-${local.iaas_vm_sfx}"
  location            = var.iaas_location
  resource_group_name = var.iaas_rg
  size                = var.iaas_linux_vm_size

  admin_username = var.iaas_admin_username

  admin_ssh_key {
    username   = var.iaas_admin_username
    public_key = file(pathexpand("~/.ssh/ssh_key/vm-key/vm-key.pub"))
  }
  disable_password_authentication = true

  network_interface_ids = [var.iaas_linux_nic_id]

  identity {
    type = "SystemAssigned"
  }

  os_disk {
    name                 = "CDRIVEXOSDISK"
    caching              = "ReadWrite"
    storage_account_type = "StandardSSD_LRS"
    disk_size_gb         = 512
  }

  source_image_reference {
    publisher = "RedHat"
    offer     = "RHEL"
    sku       = "9-lvm-gen2"
    version   = "latest"
  }
}

resource "azurerm_key_vault_access_policy" "iaas_linux_mi" {
  count = var.iaas_enabled ? 1 : 0

  key_vault_id = var.iaas_key_vault_id
  tenant_id    = azurerm_linux_virtual_machine.iaas_linux[0].identity[0].tenant_id
  object_id    = azurerm_linux_virtual_machine.iaas_linux[0].identity[0].principal_id

  secret_permissions = ["Get", "List"]
  key_permissions    = ["Get", "WrapKey", "UnwrapKey", "List"]
}
