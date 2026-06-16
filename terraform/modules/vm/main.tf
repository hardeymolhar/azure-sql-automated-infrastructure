
resource "azurerm_linux_virtual_machine" "vm" {

  count               = var.linux_vm_count
  name                = var.vm_name
  resource_group_name = var.primary_rg
  location            = var.primary_location
  size                = var.vm_size
  admin_username      = var.admin_username

  #custom_data = base64encode(templatefile("${path.module}/../scripts/cloud-init-sh.yaml", {
  #  storage_account = data.terraform_remote_state.storage.outputs.storage_account_name
  #  sas_token       = data.azurerm_storage_account_sas.script_sas.sas
  #  vault_password  = var.vault_password
  #}))


  admin_ssh_key {
    username   = var.admin_username
    public_key = file(pathexpand("~/.ssh/ssh_key/vm-key/vm-key.pub"))
  }
  disable_password_authentication = true


  network_interface_ids = [
    var.nic_id,
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
  location            = var.primary_location
  resource_group_name = var.primary_rg
  size                = "Standard_B2ms"


  admin_username = var.admin_username
  admin_password = var.admin_password



  zone = tostring((count.index % 2) + 1)

  identity {
    type = "SystemAssigned"
  }

  network_interface_ids = [
    var.db_nic_id
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



# =========================================================
# WINRM FOR ANSIBLE
# ---------------------------------------------------------
# Context  — Ansible manages this Windows VM over WinRM, and the test-env flow
#            now connects over the HTTPS (5986) listener rather than 5985/HTTP.
# Decision — open BOTH 5985 and 5986 at the host firewall (each restricted to
#            var.client_ip) and provision a self-signed-cert WinRM HTTPS listener
#            (CN = the VM computer name), mirroring the test-env run-command. The
#            paired NSG rule lives in the network module (Allow-WinRM-HTTPS, 5986).
# Rationale — Windows Server 2019 ships a 5985/HTTP listener by default but no
#            HTTPS listener; HTTPS wraps the NTLM session in TLS end-to-end. The
#            cert is self-signed, so the inventory must use
#            ansible_winrm_server_cert_validation=ignore (no CA/PKI in the sandbox).
#            The prior HTTPS listener is removed before re-creating it, so the
#            CustomScriptExtension stays idempotent across re-runs.
# =========================================================
resource "azurerm_virtual_machine_extension" "winrm" {
  name                 = "enable-winrm"
  virtual_machine_id   = azurerm_windows_virtual_machine.db_vm[0].id
  publisher            = "Microsoft.Compute"
  type                 = "CustomScriptExtension"
  type_handler_version = "1.10"

  settings = jsonencode({
    commandToExecute = <<EOT
  powershell -ExecutionPolicy Bypass -Command "$httpRule = 'WinRM-Restricted-Custom'; $httpsRule = 'WinRM-HTTPS-Restricted-Custom'; $ip = '${var.client_ip}/32'; Start-Sleep -Seconds 30; if (-not (Get-NetFirewallRule -DisplayName $httpRule -ErrorAction SilentlyContinue)) { New-NetFirewallRule -DisplayName $httpRule -Direction Inbound -Protocol TCP -LocalPort 5985 -Action Allow -RemoteAddress $ip -Profile Any } else { Set-NetFirewallRule -DisplayName $httpRule -Enabled True; Get-NetFirewallRule -DisplayName $httpRule | Get-NetFirewallAddressFilter | Set-NetFirewallAddressFilter -RemoteAddress $ip }; if (-not (Get-NetFirewallRule -DisplayName $httpsRule -ErrorAction SilentlyContinue)) { New-NetFirewallRule -DisplayName $httpsRule -Direction Inbound -Protocol TCP -LocalPort 5986 -Action Allow -RemoteAddress $ip -Profile Any } else { Set-NetFirewallRule -DisplayName $httpsRule -Enabled True; Get-NetFirewallRule -DisplayName $httpsRule | Get-NetFirewallAddressFilter | Set-NetFirewallAddressFilter -RemoteAddress $ip }; $cert = New-SelfSignedCertificate -DnsName $env:COMPUTERNAME -CertStoreLocation Cert:\LocalMachine\My; Get-ChildItem WSMan:\localhost\Listener | Where-Object { $_.Keys -match 'Transport=HTTPS' } | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue; New-Item -Path WSMan:\localhost\Listener -Transport HTTPS -Address * -HostName $env:COMPUTERNAME -CertificateThumbPrint $cert.Thumbprint -Force; Restart-Service -Name WinRM"
  EOT
  })

  depends_on = [
    azurerm_windows_virtual_machine.db_vm[0]
  ]
}
