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
# ENSURE VNET / SUBNET EXIST (shared with Node 1)
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

# =========================================================
# CREATE NSG (dedicated to Node 2)
# =========================================================

if resource_exists "az network nsg show --resource-group $RESOURCE_GROUP --name $WIN2_NSG_NAME"; then
  echo -e "${YELLOW}Windows NSG already exists. Skipping creation...${NC}"
else
  echo -e "${BLUE}Creating Windows NSG...${NC}"

  az network nsg create \
    --resource-group "$RESOURCE_GROUP" \
    --location "$LOCATION" \
    --name "$WIN2_NSG_NAME"
fi

# =========================================================
# NSG RULES (all scoped to the workstation client IP)
#   3389 -> RDP, 5985 -> WinRM (Ansible), 1433 -> SQL Server
# =========================================================

create_nsg_rule() {
  local rule_name="$1"
  local priority="$2"
  local port="$3"

  if resource_exists "az network nsg rule show --resource-group $RESOURCE_GROUP --nsg-name $WIN2_NSG_NAME --name $rule_name"; then
    echo -e "${YELLOW}NSG rule $rule_name already exists. Skipping...${NC}"
  else
    echo -e "${BLUE}Creating NSG rule $rule_name (port $port)...${NC}"

    az network nsg rule create \
      --resource-group "$RESOURCE_GROUP" \
      --nsg-name "$WIN2_NSG_NAME" \
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

if resource_exists "az network public-ip show --resource-group $RESOURCE_GROUP --name $WIN_PUBLIC_IP_NAME_2"; then
  echo -e "${YELLOW}Public IP already exists. Skipping creation...${NC}"
else
  echo -e "${BLUE}Creating Public IP...${NC}"

  az network public-ip create \
    --resource-group "$RESOURCE_GROUP" \
    --location "$LOCATION" \
    --name "$WIN_PUBLIC_IP_NAME_2" \
    --sku Standard
fi

# =========================================================
# CREATE NIC
# =========================================================

if resource_exists "az network nic show --resource-group $RESOURCE_GROUP --name $WIN_NIC_NAME_2"; then
  echo -e "${YELLOW}NIC already exists. Skipping creation...${NC}"
else
  echo -e "${BLUE}Creating NIC...${NC}"

  az network nic create \
    --resource-group "$RESOURCE_GROUP" \
    --name "$WIN_NIC_NAME_2" \
    --vnet-name "$VNET_NAME" \
    --subnet "$SUBNET_NAME" \
    --network-security-group "$WIN2_NSG_NAME" \
    --public-ip-address "$WIN_PUBLIC_IP_NAME_2"
fi

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
    --size "$WIN_VM_SIZE" \
    --admin-username "$ADMIN_USERNAME" \
    --admin-password "$ADMIN_PASSWORD" \
    --os-disk-name "$WIN_OS_DISK_2" \
    --storage-sku StandardSSD_LRS \
    --assign-identity
fi

# =========================================================
# ENABLE WINRM FOR ANSIBLE
# ---------------------------------------------------------
# Identical to Node 1: set the profile Private, Enable-PSRemoting with
# -SkipNetworkProfileCheck, widen the public WinRM firewall rule to Any (the NSG
# still locks exposure to CLIENT_IP), enable Negotiate auth + the local-account
# token policy, and restart WinRM. Each --scripts string is one line of a single
# PowerShell script run as SYSTEM on the VM.
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
    "New-NetFirewallRule -DisplayName 'WinRM-HTTP-In-Ansible' -Direction Inbound -Protocol TCP -LocalPort 5985 -Action Allow -Profile Any -RemoteAddress Any -ErrorAction SilentlyContinue" \
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
echo -e "      then vm-config.sh to apply the Ansible SQL configuration."
echo -e "${GREEN}RDP:${NC}  mstsc /v:$VM_PUBLIC_IP   (user: $ADMIN_USERNAME)"
echo -e "${GREEN}SQL:${NC}  sqlcmd -S $VM_PUBLIC_IP,1433 -U $SQL_LOGIN -P '<password>' -Q 'SELECT @@VERSION'"
echo -e "${GREEN}==========================================${NC}"
