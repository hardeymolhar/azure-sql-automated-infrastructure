# =====================================================
# IaaS SQL-on-VM track (shell parity) — module inputs + shared locals
# Source of truth: scripts/shell/test-env/{dc-vm,win-sql-vm,win-sql-vm-2,
# app-vm,win-encrypted-disks,win-encrypted-disks-2,encrypted-mgd-disks}.sh
# and env.conf.
# =====================================================

variable "iaas_enabled" {
  description = "Deploy the IaaS SQL-on-VM track resources owned by this module. Off by default."
  type        = bool
  default     = false
}

variable "iaas_resource_suffix" {
  description = "Name suffix mirroring env.conf RESOURCE_SUFFIX (VM names ms-/cs-/dc-/dc2-/vm-<suffix>)."
  type        = string
  default     = "res-ind-442"
}

variable "iaas_rg" {
  description = "Resource group for the IaaS track. Must be set when iaas_enabled = true."
  type        = string
  default     = null
}

variable "iaas_location" {
  description = "Region for the IaaS track (env.conf LOCATION)."
  type        = string
  default     = "centralindia"
}

variable "iaas_admin_username" {
  description = "Admin user for every IaaS VM (env.conf ADMIN_USERNAME; becomes SQLFCI\\sqladmin after domain promotion)."
  type        = string
  default     = "sqladmin"
}

variable "iaas_admin_password" {
  description = "Admin password for the Windows VMs (env.conf ADMIN_PASSWORD). Required when iaas_enabled = true."
  type        = string
  sensitive   = true
  default     = null
}

variable "iaas_win_vm_size" {
  description = "SQL Node 1 size (env.conf WIN_VM_SIZE)."
  type        = string
  default     = "Standard_D8s_v3"
}

variable "iaas_win_vm_size_2" {
  description = "SQL Node 2 size (env.conf WIN_VM_SIZE_2). Asymmetric with Node 1 in the shell deployment — kept for strict parity."
  type        = string
  default     = "Standard_B2ms"
}

variable "iaas_dc_vm_size" {
  description = "Domain controller size (env.conf DC_VM_SIZE)."
  type        = string
  default     = "Standard_B2ms"
}

variable "iaas_linux_vm_size" {
  description = "Linux workload VM size (env.conf VM_SIZE)."
  type        = string
  default     = "Standard_B2ms"
}

variable "iaas_win_disk_sku" {
  description = "SKU for the Windows/DC data disks (env.conf WIN_DISK_SKU)."
  type        = string
  default     = "StandardSSD_ZRS"
}

# --- wiring: network -> vm ---

variable "iaas_linux_nic_id" {
  description = "NIC id for the Linux workload VM (network module)."
  type        = string
  default     = null
}

variable "iaas_win_nic_id" {
  description = "NIC id for SQL Node 1 (network module)."
  type        = string
  default     = null
}

variable "iaas_win2_nic_id" {
  description = "NIC id for SQL Node 2 (network module)."
  type        = string
  default     = null
}

variable "iaas_dc_nic_id" {
  description = "NIC id for Domain Controller 1 (network module)."
  type        = string
  default     = null
}

variable "iaas_dc2_nic_id" {
  description = "NIC id for Domain Controller 2 (network module)."
  type        = string
  default     = null
}

# --- wiring: security -> vm ---

variable "iaas_windows_des_id" {
  description = "Disk Encryption Set id for the Windows SQL node disks (security module; output ordering guarantees the DES already holds wrap/unwrap on the vault)."
  type        = string
  default     = null
}

variable "iaas_linux_des_id" {
  description = "Disk Encryption Set id for the Linux workload VM disks (security module)."
  type        = string
  default     = null
}

variable "iaas_key_vault_id" {
  description = "IaaS Key Vault id (security module) — target of the Linux VM managed-identity access policy (app-vm.sh:223/:234). The policy lives in this module because its lifecycle is the VM identity's; placing it in security would create a security<->vm module cycle."
  type        = string
  default     = null
}

locals {
  iaas_vm_sfx = var.iaas_resource_suffix

  # env.conf: Zone 1 -> SQL Node 1 / DC1, Zone 2 -> SQL Node 2 / DC2.
  iaas_win_vm_zone  = "1"
  iaas_win_vm_zone2 = "2"
  iaas_dc_vm_zone   = "1"
  iaas_dc2_vm_zone  = "2"

  # WinRM bootstrap — the exact PowerShell the shell runs via
  # `az vm run-command invoke` on all four Windows VMs (win-sql-vm.sh:83,
  # win-sql-vm-2.sh:73, dc-vm.sh:197/:218). HTTPS (5986) listener with a
  # self-signed cert is Ansible's primary connection; 5985/HTTP stays as a
  # fallback; the NSG limits exposure to the client IP. Re-runnable: the
  # prior HTTPS listener is removed before being re-created.
  iaas_winrm_script = <<-EOT
    Set-NetConnectionProfile -NetworkCategory Private -ErrorAction SilentlyContinue
    Enable-PSRemoting -Force -SkipNetworkProfileCheck
    Set-Service -Name WinRM -StartupType Automatic
    Start-Service -Name WinRM
    Set-Item -Path WSMan:\localhost\Service\Auth\Negotiate -Value $true -Force
    $winrmCert = New-SelfSignedCertificate -DnsName $env:COMPUTERNAME -CertStoreLocation Cert:\LocalMachine\My
    Get-ChildItem WSMan:\localhost\Listener | Where-Object { $_.Keys -match 'Transport=HTTPS' } | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
    New-Item -Path WSMan:\localhost\Listener -Transport HTTPS -Address * -HostName $env:COMPUTERNAME -CertificateThumbPrint $winrmCert.Thumbprint -Force
    New-NetFirewallRule -DisplayName 'WinRM-HTTP-In-Ansible' -Direction Inbound -Protocol TCP -LocalPort 5985 -Action Allow -Profile Any -RemoteAddress Any -ErrorAction SilentlyContinue
    New-NetFirewallRule -DisplayName 'WinRM-HTTPS-In-Ansible' -Direction Inbound -Protocol TCP -LocalPort 5986 -Action Allow -Profile Any -RemoteAddress Any -ErrorAction SilentlyContinue
    Set-NetFirewallRule -Name 'WINRM-HTTP-In-TCP-PUBLIC' -RemoteAddress Any -ErrorAction SilentlyContinue
    New-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' -Name LocalAccountTokenFilterPolicy -Value 1 -PropertyType DWord -Force
    Restart-Service -Name WinRM
  EOT
}
