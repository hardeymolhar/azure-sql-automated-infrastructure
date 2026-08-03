#!/bin/bash
source "$(dirname "$0")/env.conf"
set -euo pipefail

# =========================================================
# WINDOWS SQL SERVER VM DEPLOYMENT (az CLI)
# ---------------------------------------------------------
# Deploys a Windows Server VM with SQL Server 2022 (Developer)
# pre-installed from the Azure Marketplace image, opens the
# required ports (RDP / WinRM / SQL) scoped to the client IP,
# and enables WinRM so Ansible can finish the ready-to-connect
# SQL configuration (see ansible/playbooks/sql-server-on-windows.yml).
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
# CREATE WINDOWS SQL VM
# =========================================================

if resource_exists "az vm show --resource-group $RESOURCE_GROUP --name $WIN_VM_NAME"; then
  echo -e "${YELLOW}Windows VM already exists. Skipping creation...${NC}"
else
  echo -e "${BLUE}Creating Windows SQL Server VM...${NC}"

  az vm create \
    --resource-group "$RESOURCE_GROUP" \
    --location "$LOCATION" \
    --zone "$WIN_VM_ZONE" \
    --name "$WIN_VM_NAME" \
    --nics "$WIN_NIC_NAME" \
    --image "$WIN_IMAGE" \
    --size "$WIN_VM_SIZE" \
    --admin-username "$ADMIN_USERNAME" \
    --admin-password "$ADMIN_PASSWORD" \
    --os-disk-name "$WIN_OS_DISK" \
    --storage-sku StandardSSD_ZRS \
    --assign-identity
fi

# =========================================================
# ENABLE WINRM FOR ANSIBLE
# ---------------------------------------------------------
# Ansible manages Windows over WinRM. We open BOTH listener ports at the host
# firewall (5985/HTTP and 5986/HTTPS) but Ansible connects over the HTTPS (5986)
# listener, which wraps the NTLM/Negotiate session in TLS end-to-end rather than
# relying on message-level encryption over plaintext HTTP. A self-signed cert
# (CN = the VM computer name) backs the listener; the inventory sets
# ansible_winrm_server_cert_validation=ignore, so no CA/PKI is required in the
# sandbox. The 5985/HTTP listener stays enabled as a fallback.
#
# Order/flags matter (per Microsoft docs):
#  - Set the connection profile to Private BEFORE Enable-PSRemoting, and pass
#    -SkipNetworkProfileCheck, so remoting is enabled even on a Public profile.
#  - On Windows SERVER SKUs, Enable-PSRemoting's public WinRM firewall rule is
#    scoped to the LOCAL SUBNET only. Ansible connects over the internet (via the
#    public IP, a different subnet), so we must widen WINRM-HTTP-In-TCP-PUBLIC to
#    RemoteAddress=Any (the documented fix) — the NSG still limits exposure to
#    CLIENT_IP. Each --scripts string is one line of a single PowerShell script
#    run as SYSTEM on the VM.
#  - The HTTPS listener needs a server cert: New-SelfSignedCertificate creates one
#    and we bind it to a fresh WSMan HTTPS listener, removing any prior HTTPS
#    listener first so the run-command stays re-runnable (re-creating an existing
#    Address=*+Transport=HTTPS listener otherwise errors).
# =========================================================

echo -e "${BLUE}Enabling WinRM on the VM for Ansible...${NC}"

az vm run-command invoke \
  --resource-group "$RESOURCE_GROUP" \
  --name "$WIN_VM_NAME" \
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
  --name "$WIN_VM_NAME" \
  -d \
  --query publicIps \
  -o tsv)

# =========================================================
# VALIDATION
# =========================================================

echo -e "${GREEN}==========================================${NC}"
echo -e "${GREEN}Windows SQL Server VM deployed successfully.${NC}"
echo -e "${GREEN}==========================================${NC}"
echo -e "${GREEN}VM Name:${NC}    $WIN_VM_NAME"
echo -e "${GREEN}Public IP:${NC}  $VM_PUBLIC_IP"
echo ""
echo -e "${GREEN}Next:${NC} run vm-stg-ind-49.sh to apply the Ansible SQL configuration."
echo -e "${GREEN}RDP:${NC}  mstsc /v:$VM_PUBLIC_IP   (user: $ADMIN_USERNAME)"
echo -e "${GREEN}SQL:${NC}  sqlcmd -S $VM_PUBLIC_IP,1433 -U $SQL_LOGIN -P '<password>' -Q 'SELECT @@VERSION'"
echo -e "${GREEN}==========================================${NC}"
