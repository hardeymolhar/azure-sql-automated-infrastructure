#!/bin/bash
source "$(dirname "$0")/env.conf"
set -euo pipefail


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
# CREATE VNET
# =========================================================

if resource_exists "az network vnet show --resource-group $RESOURCE_GROUP --name $VNET_NAME"; then
  echo -e "${YELLOW}VNET already exists. Skipping creation...${NC}"
else
  echo -e "${BLUE}Creating VNET...${NC}"

  az network vnet create \
    --resource-group "$RESOURCE_GROUP" \
    --location "$LOCATION" \
    --name "$VNET_NAME" \
    --address-prefixes "$VNET_ADDRESS_PREFIX" \
    --subnet-name "$SUBNET_NAME" \
    --subnet-prefixes 10.10.1.0/24
fi


# =========================================================
# ENABLE SERVICE ENDPOINTS
# =========================================================

echo -e "${BLUE}Configuring subnet service endpoints...${NC}"

az network vnet subnet update \
  --resource-group "$RESOURCE_GROUP" \
  --vnet-name "$VNET_NAME" \
  --name "$SUBNET_NAME" \
  --service-endpoints Microsoft.Storage Microsoft.KeyVault Microsoft.Sql

# =========================================================
# CREATE NSG
# =========================================================

if resource_exists "az network nsg show --resource-group $RESOURCE_GROUP --name $NSG_NAME"; then
  echo -e "${YELLOW}NSG already exists. Skipping creation...${NC}"
else
  echo -e "${BLUE}Creating NSG...${NC}"

  az network nsg create \
    --resource-group "$RESOURCE_GROUP" \
    --location "$LOCATION" \
    --name "$NSG_NAME"
fi

# =========================================================
# ALLOW SSH ONLY FROM CLIENT IP
# =========================================================

if resource_exists "az network nsg rule show --resource-group $RESOURCE_GROUP --nsg-name $NSG_NAME --name Allow-SSH-Client-IP"; then
  echo -e "${YELLOW}NSG rule already exists. Skipping creation...${NC}"
else
  echo -e "${BLUE}Creating NSG rule for SSH access...${NC}"

  az network nsg rule create \
    --resource-group "$RESOURCE_GROUP" \
    --nsg-name "$NSG_NAME" \
    --name "Allow-SSH-Client-IP" \
    --priority 1000 \
    --direction Inbound \
    --access Allow \
    --protocol Tcp \
    --source-address-prefixes "$CLIENT_IP" \
    --source-port-ranges "*" \
    --destination-port-ranges 22
fi

# =========================================================
# CREATE PUBLIC IP
# =========================================================

if resource_exists "az network public-ip show --resource-group $RESOURCE_GROUP --name $PUBLIC_IP_NAME"; then
  echo -e "${YELLOW}Public IP already exists. Skipping creation...${NC}"
else
  echo -e "${BLUE}Creating Public IP...${NC}"

  az network public-ip create \
    --resource-group "$RESOURCE_GROUP" \
    --location "$LOCATION" \
    --name "$PUBLIC_IP_NAME" \
    --sku Standard
fi



# =========================================================
# CREATE NIC
# =========================================================

if resource_exists "az network nic show --resource-group $RESOURCE_GROUP --name $NIC_NAME"; then
  echo -e "${YELLOW}NIC already exists. Skipping creation...${NC}"
else
  echo -e "${BLUE}Creating NIC...${NC}"

  az network nic create \
    --resource-group "$RESOURCE_GROUP" \
    --name "$NIC_NAME" \
    --vnet-name "$VNET_NAME" \
    --subnet "$SUBNET_NAME" \
    --network-security-group "$NSG_NAME" \
    --public-ip-address "$PUBLIC_IP_NAME" \
    --location "$LOCATION"
fi





# =========================================================
# SECOND WINDOWS VM NETWORK CONFIG (shared VNET/SUBNET with Node 1)
# ==========================================================

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

if resource_exists "az network vnet subnet show --resource-group $RESOURCE_GROUP --name $WIN_SUBNET_NAME"; then
  echo -e "${YELLOW}Subnet  already exists. Skipping creation...${NC}"
else
  echo -e "${BLUE}Creating Subnet...${NC}"
az network vnet subnet create \
    --resource-group "$RESOURCE_GROUP" \
    --vnet-name "$VNET_NAME" \
    --name "$WIN_SUBNET_NAME" \
    --address-prefixes "$WIN_SUBNET_PREFIX"

  fi

# =========================================================
# ENABLE SERVICE ENDPOINTS ON WINDOWS SQL SUBNET
# ---------------------------------------------------------
# Microsoft.Storage is required so the storage account VNet rule can allow
# traffic from this subnet (Cloud Witness + lab-file SAS downloads).
# =========================================================
echo -e "${BLUE}Configuring service endpoints on Windows SQL subnet...${NC}"
az network vnet subnet update \
  --resource-group "$RESOURCE_GROUP" \
  --vnet-name "$VNET_NAME" \
  --name "$WIN_SUBNET_NAME" \
  --service-endpoints Microsoft.Storage

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
#   3389 -> RDP, 5985/5986 -> WinRM (Ansible connects on 5986/HTTPS; 5985/HTTP
#   kept as fallback), 1433 -> SQL Server
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
create_nsg_rule "Allow-WinRM-HTTP" 1010 "$WIN_WINRM_PORT"
create_nsg_rule "Allow-WinRM-HTTPS" 1011 "$HTTPS_WIN_WINRM_PORT"
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
    --public-ip-address "$WIN_PUBLIC_IP_NAME" \
    --location "$LOCATION"
fi
#########################################################
# SECOND WINDOWSVM NETWORK SECTION
##########################################################


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
#   3389 -> RDP, 5985/5986 -> WinRM (Ansible connects on 5986/HTTPS; 5985/HTTP
#   kept as fallback), 1433 -> SQL Server
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
create_nsg_rule "Allow-WinRM-HTTP" 1010 "$WIN_WINRM_PORT"
create_nsg_rule "Allow-WinRM-HTTPS" 1011 "$HTTPS_WIN_WINRM_PORT"
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
    --public-ip-address "$WIN_PUBLIC_IP_NAME_2" \
    --location "$LOCATION"
fi
