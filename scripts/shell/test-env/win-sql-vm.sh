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
# ENSURE VNET / SUBNET EXIST
# =========================================================

if resource_exists "az network vnet show --resource-group $RESOURCE_GROUP --name $VNET_NAME"; then
  echo -e "${YELLOW}VNET already exists. Skipping creation...${NC}"
else
  echo -e "${BLUE}Creating VNET...${NC}"

  az network vnet create \
    --resource-group "$RESOURCE_GROUP" \
    --location "$LOCATION" \
    --name "$VNET_NAME" \
    --subnet-name "$SUBNET_NAME" \
    --subnet-prefixes 10.10.1.0/24
fi

if resource_exists "az network vnet subnet show --resource-group $RESOURCE_GROUP --name "WindowsSubnet""; then
  echo -e "${YELLOW}Subnet  already exists. Skipping creation...${NC}"
else
  echo -e "${BLUE}Creating Subnet...${NC}"
az network vnet subnet create \
    --resource-group "$RESOURCE_GROUP" \
    --vnet-name "$VNET_NAME" \
    --name "WindowsSubnet" \
    --address-prefixes "10.10.2.0/24"

  fi

# =========================================================
# CREATE NSG
# =========================================================

if resource_exists "az network nsg show --resource-group $RESOURCE_GROUP --name $WIN_NSG_NAME"; then
  echo -e "${YELLOW}Windows NSG already exists. Skipping creation...${NC}"
else
  echo -e "${BLUE}Creating Windows NSG...${NC}"

  az network nsg create \
    --resource-group "$RESOURCE_GROUP" \
    --location "$LOCATION" \
    --name "$WIN_NSG_NAME"
fi





# =========================================================
# NSG RULES (all scoped to the workstation client IP)
#   3389 -> RDP, 5985 -> WinRM (Ansible), 1433 -> SQL Server
# =========================================================

create_nsg_rule() {
  local rule_name="$1"
  local priority="$2"
  local port="$3"

  if resource_exists "az network nsg rule show --resource-group $RESOURCE_GROUP --nsg-name $WIN_NSG_NAME --name $rule_name"; then
    echo -e "${YELLOW}NSG rule $rule_name already exists. Skipping...${NC}"
  else
    echo -e "${BLUE}Creating NSG rule $rule_name (port $port)...${NC}"

    az network nsg rule create \
      --resource-group "$RESOURCE_GROUP" \
      --nsg-name "$WIN_NSG_NAME" \
      --name "$rule_name" \
      --priority "$priority" \
      --direction Inbound \
      --access Allow \
      --protocol Tcp \
      --source-address-prefixes "$CLIENT_IP" \
      --source-port-ranges "*" \
      --destination-port-ranges "$port"
  fi
}

create_nsg_rule "Allow-RDP-Client-IP" 1000 3389
create_nsg_rule "Allow-WinRM-Client-IP" 1010 "$WIN_WINRM_PORT"
create_nsg_rule "Allow-SQL-Client-IP" 1020 1433

# =========================================================
# CREATE PUBLIC IP
# =========================================================

if resource_exists "az network public-ip show --resource-group $RESOURCE_GROUP --name $WIN_PUBLIC_IP_NAME"; then
  echo -e "${YELLOW}Public IP already exists. Skipping creation...${NC}"
else
  echo -e "${BLUE}Creating Public IP...${NC}"

  az network public-ip create \
    --resource-group "$RESOURCE_GROUP" \
    --location "$LOCATION" \
    --name "$WIN_PUBLIC_IP_NAME" \
    --sku Standard
fi

# =========================================================
# CREATE NIC
# =========================================================

if resource_exists "az network nic show --resource-group $RESOURCE_GROUP --name $WIN_NIC_NAME"; then
  echo -e "${YELLOW}NIC already exists. Skipping creation...${NC}"
else
  echo -e "${BLUE}Creating NIC...${NC}"

  az network nic create \
    --resource-group "$RESOURCE_GROUP" \
    --name "$WIN_NIC_NAME" \
    --vnet-name "$VNET_NAME" \
    --subnet "$SUBNET_NAME" \
    --network-security-group "$WIN_NSG_NAME" \
    --public-ip-address "$WIN_PUBLIC_IP_NAME"
fi

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
    --storage-sku StandardSSD_LRS \
    --assign-identity
fi

# =========================================================
# ENABLE WINRM FOR ANSIBLE
# ---------------------------------------------------------
# Ansible manages Windows over WinRM. We enable the HTTP (5985)
# listener and use NTLM/Negotiate from the inventory, which
# encrypts the payload over HTTP. This is a sandbox-grade setup;
# a production host should use the HTTPS (5986) listener with a
# proper certificate instead.
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
    "New-NetFirewallRule -DisplayName 'WinRM-HTTP-In-Ansible' -Direction Inbound -Protocol TCP -LocalPort 5985 -Action Allow -Profile Any -RemoteAddress Any -ErrorAction SilentlyContinue" \
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
echo -e "${GREEN}Next:${NC} run vm-config.sh to apply the Ansible SQL configuration."
echo -e "${GREEN}RDP:${NC}  mstsc /v:$VM_PUBLIC_IP   (user: $ADMIN_USERNAME)"
echo -e "${GREEN}SQL:${NC}  sqlcmd -S $VM_PUBLIC_IP,1433 -U $SQL_LOGIN -P '<password>' -Q 'SELECT @@VERSION'"
echo -e "${GREEN}==========================================${NC}"
