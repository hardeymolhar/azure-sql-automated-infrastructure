#!/bin/bash
source "$(dirname "$0")/env.conf"
set -euo pipefail

# =========================================================
# WINDOWS SQL SERVER VM 2 — SQL NODE 2 (az CLI)
# ---------------------------------------------------------
# Second node of the cross-zone SQL architecture:
#   Zone 1 -> SQL Node 1 ($WIN_VM_NAME,   win-sql-vm.sh)
#   Zone 2 -> SQL Node 2 ($WIN_VM_NAME_2, this script)
#
# Same configuration/logic as win-sql-vm.sh — only the per-VM resources differ
# (NIC / public IP / OS disk / NSG / zone). Node 2 shares the VNet + subnet with
# Node 1 but uses its own NSG ($WIN2_NSG_NAME) and is pinned to $WIN_VM_ZONE_2.
# Opens RDP / WinRM / SQL scoped to the client IP and enables WinRM so Ansible
# can finish the SQL configuration (ansible/playbooks/sql-server-on-windows.yml).
# =========================================================

# =========================================================
# HELPER FUNCTIONS
# =========================================================

resource_exists() {
  local resource_check_command="$1"

  if eval "$resource_check_command" >/dev/null 2>&1; then
    return 0
  else
    return 1
  fi
}


# =========================================================
# CREATE WINDOWS SQL VM (Zone 2)
# =========================================================

if resource_exists "az vm show --resource-group $RESOURCE_GROUP --name $WIN_VM_NAME_2"; then
  echo -e "${YELLOW}Windows VM already exists. Skipping creation...${NC}"
else
  echo -e "${BLUE}Creating Windows SQL Server VM (Node 2)...${NC}"

  az vm create \
    --resource-group "$RESOURCE_GROUP" \
    --location "$LOCATION" \
    --zone "$WIN_VM_ZONE_2" \
    --name "$WIN_VM_NAME_2" \
    --nics "$WIN_NIC_NAME_2" \
    --image "$WIN_IMAGE" \
    --size "$WIN_VM_SIZE_2" \
    --admin-username "$ADMIN_USERNAME" \
    --admin-password "$ADMIN_PASSWORD" \
    --os-disk-name "$WIN_OS_DISK_2" \
    --storage-sku StandardSSD_ZRS \
    --assign-identity
fi

# =========================================================
# ENABLE WINRM FOR ANSIBLE
# ---------------------------------------------------------
# Identical to Node 1: set the profile Private, Enable-PSRemoting with
# -SkipNetworkProfileCheck, widen the public WinRM firewall rule to Any (the NSG
# still locks exposure to CLIENT_IP), enable Negotiate auth + the local-account
# token policy. We also create a self-signed cert and an HTTPS (5986) WinRM
# listener — Ansible's connection target — open BOTH 5985 and 5986 at the host
# firewall (5985/HTTP kept as a fallback), and restart WinRM. The prior HTTPS
# listener is removed first so the run-command stays re-runnable. Each --scripts
# string is one line of a single PowerShell script run as SYSTEM on the VM.
# =========================================================

echo -e "${BLUE}Enabling WinRM on the VM for Ansible...${NC}"

az vm run-command invoke \
  --resource-group "$RESOURCE_GROUP" \
  --name "$WIN_VM_NAME_2" \
  --command-id RunPowerShellScript \
  --scripts \
    "Set-NetConnectionProfile -NetworkCategory Private -ErrorAction SilentlyContinue" \
    "Enable-PSRemoting -Force -SkipNetworkProfileCheck" \
    "Set-Service -Name WinRM -StartupType Automatic" \
    "Start-Service -Name WinRM" \
    "Set-Item -Path WSMan:\\localhost\\Service\\Auth\\Negotiate -Value \$true -Force" \
    "\$winrmCert = New-SelfSignedCertificate -DnsName \$env:COMPUTERNAME -CertStoreLocation Cert:\\LocalMachine\\My" \
    "Get-ChildItem WSMan:\\localhost\\Listener | Where-Object { \$_.Keys -match 'Transport=HTTPS' } | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue" \
    "New-Item -Path WSMan:\\localhost\\Listener -Transport HTTPS -Address * -HostName \$env:COMPUTERNAME -CertificateThumbPrint \$winrmCert.Thumbprint -Force" \
    "New-NetFirewallRule -DisplayName 'WinRM-HTTP-In-Ansible' -Direction Inbound -Protocol TCP -LocalPort 5985 -Action Allow -Profile Any -RemoteAddress Any -ErrorAction SilentlyContinue" \
    "New-NetFirewallRule -DisplayName 'WinRM-HTTPS-In-Ansible' -Direction Inbound -Protocol TCP -LocalPort 5986 -Action Allow -Profile Any -RemoteAddress Any -ErrorAction SilentlyContinue" \
    "Set-NetFirewallRule -Name 'WINRM-HTTP-In-TCP-PUBLIC' -RemoteAddress Any -ErrorAction SilentlyContinue" \
    "New-ItemProperty -Path 'HKLM:\\SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\Policies\\System' -Name LocalAccountTokenFilterPolicy -Value 1 -PropertyType DWord -Force" \
    "Restart-Service -Name WinRM"

# =========================================================
# FETCH VM PUBLIC IP
# =========================================================

VM_PUBLIC_IP=$(az vm show \
  --resource-group "$RESOURCE_GROUP" \
  --name "$WIN_VM_NAME_2" \
  -d \
  --query publicIps \
  -o tsv)

# =========================================================
# VALIDATION
# =========================================================

echo -e "${GREEN}==========================================${NC}"
echo -e "${GREEN}Windows SQL Server VM (Node 2) deployed successfully.${NC}"
echo -e "${GREEN}==========================================${NC}"
echo -e "${GREEN}VM Name:${NC}    $WIN_VM_NAME_2"
echo -e "${GREEN}Zone:${NC}       $WIN_VM_ZONE_2"
echo -e "${GREEN}Public IP:${NC}  $VM_PUBLIC_IP"
echo ""
echo -e "${GREEN}Next:${NC} run win-encrypted-disks-2.sh to attach its encrypted disks,"
echo -e "      then vm-res-ind-112.sh to apply the Ansible SQL configuration."
echo -e "${GREEN}RDP:${NC}  mstsc /v:$VM_PUBLIC_IP   (user: $ADMIN_USERNAME)"
echo -e "${GREEN}SQL:${NC}  sqlcmd -S $VM_PUBLIC_IP,1433 -U $SQL_LOGIN -P '<password>' -Q 'SELECT @@VERSION'"
echo -e "${GREEN}==========================================${NC}"
