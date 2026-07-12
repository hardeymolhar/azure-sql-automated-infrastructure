#!/bin/bash
source "$(dirname "$0")/env.conf"
set -euo pipefail

# =========================================================
# DOMAIN CONTROLLER VM DEPLOYMENT (az CLI)
# ---------------------------------------------------------
# Deploys the dedicated Windows Server 2022 VM that becomes the Active Directory
# Domain Controller (AD DS + DNS). This script only CREATES the VM and enables
# WinRM; the AD DS role install + forest promotion + DNS forwarders are done
# in-guest by ansible/playbooks/configure-domain-controller.yml (which runs first
# in vm-res-ind-190.sh, before any SQL-node domain join).
#
# Networking (dedicated DC subnet/NSG, static private IP DC_PRIVATE_IP) is created
# by network.sh, so this VM just attaches to the pre-created DC_NIC_NAME. The DC
# is a plain member/standalone server until the Ansible play promotes it.
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
# CREATE DOMAIN CONTROLLER VM
# =========================================================

if resource_exists "az vm show --resource-group $RESOURCE_GROUP --name $DC_VM_NAME"; then
  echo -e "${YELLOW}Domain Controller VM already exists. Skipping creation...${NC}"
else
  echo -e "${BLUE}Creating Domain Controller VM...${NC}"

  az vm create \
    --resource-group "$RESOURCE_GROUP" \
    --location "$LOCATION" \
    --zone "$DC_VM_ZONE" \
    --name "$DC_VM_NAME" \
    --nics "$DC_NIC_NAME" \
    --image "$WIN_IMAGE" \
    --size "$DC_VM_SIZE" \
    --admin-username "$ADMIN_USERNAME" \
    --admin-password "$ADMIN_PASSWORD" \
    --os-disk-name "$DC_OS_DISK" \
    --storage-sku StandardSSD_ZRS \
    --assign-identity
fi


if resource_exists "az vm show --resource-group $RESOURCE_GROUP --name $DC2_VM_NAME"; then
  echo -e "${YELLOW}Domain Controller VM already exists. Skipping creation...${NC}"
else
  echo -e "${BLUE}Creating Domain Controller VM...${NC}"

  az vm create \
    --resource-group "$RESOURCE_GROUP" \
    --location "$LOCATION" \
    --zone "$DC2_VM_ZONE" \
    --name "$DC2_VM_NAME" \
    --nics "$DC2_NIC_NAME" \
    --image "$WIN_IMAGE" \
    --size "$DC_VM_SIZE" \
    --admin-username "$ADMIN_USERNAME" \
    --admin-password "$ADMIN_PASSWORD" \
    --os-disk-name "$DC2_OS_DISK" \
    --storage-sku StandardSSD_ZRS \
    --assign-identity
fi


# =========================================================
# CREATE AND ATTACH THE MANAGED DISK (LUN 0)
# ---------------------------------------------------------
# The DC VM needs a dedicated managed disk for the AD DS + DNS database and logs.
# The disk is created in Zone 1 so it can attach to the Zone-1 DC VM. The disk is attached with caching None (per Microsoft guidance for AD DS
# + DNS). The disk is created and attached in this script so that the Ansible play can assume it exists
# =========================================================


if resource_exists "az disk show --resource-group $RESOURCE_GROUP --name $DC_DISK_NAME"; then

    echo -e "${YELLOW}Managed disk ${DC_DISK_NAME} already exists. Skipping creation...${NC}"

else

    echo -e "${BLUE}Creating managed disk for Domain Controller...${NC}"

    az disk create \
        --resource-group "$RESOURCE_GROUP" \
        --name "$DC_DISK_NAME" \
        --location "$LOCATION" \
        --zone 1 \
        --size-gb 4098 \
        --sku "$WIN_DISK_SKU"

    echo -e "${GREEN}Managed disk ${DC_DISK_NAME} created successfully.${NC}"

fi

# Attach the managed disk if it isn't already attached

ATTACHED_DISK=$(az vm show \
    --resource-group "$RESOURCE_GROUP" \
    --name "$DC_VM_NAME" \
    --query "storageProfile.dataDisks[?name=='${DC_DISK_NAME}'].name" \
    -o tsv)

if [[ "$ATTACHED_DISK" == "$DC_DISK_NAME" ]]; then

    echo -e "${YELLOW}Managed disk ${DC_DISK_NAME} is already attached to ${DC_VM_NAME}. Skipping...${NC}"

else

    echo -e "${BLUE}Attaching managed disk ${DC_DISK_NAME} to ${DC_VM_NAME}...${NC}"

    az vm disk attach \
        --resource-group "$RESOURCE_GROUP" \
        --vm-name "$DC_VM_NAME" \
        --name "$DC_DISK_NAME" \
        --caching None

    echo -e "${GREEN}Managed disk ${DC_DISK_NAME} attached successfully.${NC}"

fi




if resource_exists "az disk show --resource-group $RESOURCE_GROUP --name $DC2_DISK_NAME"; then

    echo -e "${YELLOW}Managed disk ${DC2_DISK_NAME} already exists. Skipping creation...${NC}"

else

    echo -e "${BLUE}Creating managed disk for Domain Controller...${NC}"

    az disk create \
        --resource-group "$RESOURCE_GROUP" \
        --name "$DC2_DISK_NAME" \
        --location "$LOCATION" \
        --zone "$DC2_VM_ZONE" \
        --size-gb 4098 \
        --sku "$WIN_DISK_SKU"

    echo -e "${GREEN}Managed disk ${DC2_DISK_NAME} created successfully.${NC}"

fi

# Attach the managed disk if it isn't already attached

ATTACHED_DISK=$(az vm show \
    --resource-group "$RESOURCE_GROUP" \
    --name "$DC2_VM_NAME" \
    --query "storageProfile.dataDisks[?name=='${DC2_DISK_NAME}'].name" \
    -o tsv)

if [[ "$ATTACHED_DISK" == "$DC2_DISK_NAME" ]]; then

    echo -e "${YELLOW}Managed disk ${DC2_DISK_NAME} is already attached to ${DC2_VM_NAME}. Skipping...${NC}"

else

    echo -e "${BLUE}Attaching managed disk ${DC2_DISK_NAME} to ${DC2_VM_NAME}...${NC}"

    az vm disk attach \
        --resource-group "$RESOURCE_GROUP" \
        --vm-name "$DC2_VM_NAME" \
        --name "$DC2_DISK_NAME" \
        --caching None

    echo -e "${GREEN}Managed disk ${DC2_DISK_NAME} attached successfully.${NC}"

fi

# =========================================================
# ENABLE WINRM FOR ANSIBLE
# ---------------------------------------------------------
# Identical listener setup to the SQL nodes (see win-sql-vm.sh for the full
# rationale): Ansible connects over the HTTPS (5986) listener wrapping NTLM in
# TLS, backed by a self-signed cert (inventory sets
# ansible_winrm_server_cert_validation=ignore). The 5985/HTTP listener stays as a
# fallback. NSG still limits exposure to CLIENT_IP. This runs as SYSTEM and is
# re-runnable (the HTTPS listener is removed before being re-created).
# =========================================================

echo -e "${BLUE}Enabling WinRM on the Domain Controller VM for Ansible...${NC}"

az vm run-command invoke \
  --resource-group "$RESOURCE_GROUP" \
  --name "$DC_VM_NAME" \
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

    echo -e "${BLUE}Enabling WinRM on the Domain Controller VM2 for Ansible...${NC}"

az vm run-command invoke \
  --resource-group "$RESOURCE_GROUP" \
  --name "$DC2_VM_NAME" \
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
# FETCH VM PUBLIC IP + VALIDATION
# =========================================================

DC_PUBLIC_IP=$(az vm show \
  --resource-group "$RESOURCE_GROUP" \
  --name "$DC_VM_NAME" \
  -d \
  --query publicIps \
  -o tsv)

DC2_PUBLIC_IP=$(az vm show \
  --resource-group "$RESOURCE_GROUP" \
  --name "$DC2_VM_NAME" \
  -d \
  --query publicIps \
  -o tsv)

echo -e "${GREEN}==========================================${NC}"
echo -e "${GREEN}Domain Controller VM deployed successfully.${NC}"
echo -e "${GREEN}==========================================${NC}"
echo -e "${GREEN}VM Name:${NC}      $DC_VM_NAME"
echo -e "${GREEN}Public IP:${NC}    $DC_PUBLIC_IP"
echo -e "${GREEN}Private IP:${NC}   $DC_PRIVATE_IP"
echo -e "${GREEN}AD domain:${NC}    $AD_DOMAIN_NAME ($AD_NETBIOS_NAME)"
echo ""
echo -e "${GREEN}Next:${NC} vm-res-ind-190.sh runs configure-domain-controller.yml to promote this host."
echo -e "${GREEN}==========================================${NC}"
