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

#########################################################
# DOMAIN CONTROLLER NETWORK SECTION (AD DS + DNS)
# -------------------------------------------------------
# A DEDICATED subnet + NSG + static-IP NIC for the Windows Server 2022 Domain
# Controller. Kept separate from the SQL subnet so AD traffic is isolated and the
# DC has a stable private IP (DC_PRIVATE_IP) the SQL nodes point their DNS at.
#########################################################

# =========================================================
# CREATE DC SUBNET (shared VNET with the SQL nodes)
# =========================================================

if resource_exists "az network vnet subnet show --resource-group $RESOURCE_GROUP --vnet-name $VNET_NAME --name $DC_SUBNET_NAME"; then
  echo -e "${YELLOW}DC subnet already exists. Skipping creation...${NC}"
else
  echo -e "${BLUE}Creating DC subnet ($DC_SUBNET_PREFIX)...${NC}"

  az network vnet subnet create \
    --resource-group "$RESOURCE_GROUP" \
    --vnet-name "$VNET_NAME" \
    --name "$DC_SUBNET_NAME" \
    --address-prefixes "$DC_SUBNET_PREFIX"
fi

# =========================================================
# CREATE DC NSG
# =========================================================

if resource_exists "az network nsg show --resource-group $RESOURCE_GROUP --name $DC_NSG_NAME"; then
  echo -e "${YELLOW}DC NSG already exists. Skipping creation...${NC}"
else
  echo -e "${BLUE}Creating DC NSG...${NC}"

  az network nsg create \
    --resource-group "$RESOURCE_GROUP" \
    --location "$LOCATION" \
    --name "$DC_NSG_NAME"
fi

# =========================================================
# DC NSG RULES
# ---------------------------------------------------------
# AD DS + DNS service ports are opened to the VNet only (intra-VNet domain
# traffic). Admin ports (RDP / WinRM) stay scoped to the workstation CLIENT_IP,
# matching the SQL-node convention. TCP and UDP ranges are grouped into single
# rules to keep the rule count low. Port map (Microsoft AD DS firewall guidance):
#   53 DNS, 88 Kerberos, 135 RPC-EPM, 389 LDAP, 445 SMB, 464 Kerberos-pwd,
#   636 LDAPS, 3268/3269 Global Catalog, 49152-65535 dynamic RPC, 123 W32Time.
# =========================================================

create_dc_nsg_rule() {
  local rule_name="$1"
  local priority="$2"
  local protocol="$3"
  local source="$4"
  shift 4
  local ports=("$@")

  if resource_exists "az network nsg rule show --resource-group $RESOURCE_GROUP --nsg-name $DC_NSG_NAME --name $rule_name"; then
    echo -e "${YELLOW}DC NSG rule $rule_name already exists. Skipping...${NC}"
  else
    echo -e "${BLUE}Creating DC NSG rule $rule_name ($protocol ${ports[*]})...${NC}"

    az network nsg rule create \
      --resource-group "$RESOURCE_GROUP" \
      --nsg-name "$DC_NSG_NAME" \
      --name "$rule_name" \
      --priority "$priority" \
      --direction Inbound \
      --access Allow \
      --protocol "$protocol" \
      --source-address-prefixes "$source" \
      --source-port-ranges "*" \
      --destination-port-ranges "${ports[@]}"
  fi
}

create_dc_nsg_rule "Allow-AD-TCP"  1000 Tcp VirtualNetwork 53 88 135 389 445 464 636 3268 3269 49152-65535
create_dc_nsg_rule "Allow-AD-UDP"  1010 Udp VirtualNetwork 53 88 123 389 464
create_dc_nsg_rule "Allow-RDP-Client-IP" 1100 Tcp "$CLIENT_IP" 3389
create_dc_nsg_rule "Allow-WinRM" 1110 Tcp "$CLIENT_IP" "$WIN_WINRM_PORT" "$HTTPS_WIN_WINRM_PORT"

# =========================================================
# CREATE DC PUBLIC IP
# =========================================================

if resource_exists "az network public-ip show --resource-group $RESOURCE_GROUP --name $DC_PUBLIC_IP_NAME"; then
  echo -e "${YELLOW}DC Public IP already exists. Skipping creation...${NC}"
else
  echo -e "${BLUE}Creating DC Public IP...${NC}"

  az network public-ip create \
    --resource-group "$RESOURCE_GROUP" \
    --location "$LOCATION" \
    --name "$DC_PUBLIC_IP_NAME" \
    --sku Standard
fi


if resource_exists "az network public-ip show --resource-group $RESOURCE_GROUP --name $DC2_PUBLIC_IP_NAME"; then
  echo -e "${YELLOW}DC Public IP already exists. Skipping creation...${NC}"
else
  echo -e "${BLUE}Creating DC Public IP...${NC}"

  az network public-ip create \
    --resource-group "$RESOURCE_GROUP" \
    --location "$LOCATION" \
    --name "$DC2_PUBLIC_IP_NAME" \
    --sku Standard
fi

# =========================================================
# CREATE DC NIC (static private IP)
# =========================================================

if resource_exists "az network nic show --resource-group $RESOURCE_GROUP --name $DC_NIC_NAME"; then
  echo -e "${YELLOW}DC NIC already exists. Skipping creation...${NC}"
else
  echo -e "${BLUE}Creating DC NIC with static IP $DC_PRIVATE_IP...${NC}"

  az network nic create \
    --resource-group "$RESOURCE_GROUP" \
    --name "$DC_NIC_NAME" \
    --vnet-name "$VNET_NAME" \
    --subnet "$DC_SUBNET_NAME" \
    --network-security-group "$DC_NSG_NAME" \
    --public-ip-address "$DC_PUBLIC_IP_NAME" \
    --private-ip-address "$DC_PRIVATE_IP" \
    --location "$LOCATION"
fi

if resource_exists "az network nic show --resource-group $RESOURCE_GROUP --name $DC2_NIC_NAME"; then
  echo -e "${YELLOW}DC NIC already exists. Skipping creation...${NC}"
else
  echo -e "${BLUE}Creating DC NIC with static IP $DC2_PRIVATE_IP...${NC}"

  az network nic create \
    --resource-group "$RESOURCE_GROUP" \
    --name "$DC2_NIC_NAME" \
    --vnet-name "$VNET_NAME" \
    --subnet "$DC_SUBNET_NAME" \
    --network-security-group "$DC_NSG_NAME" \
    --public-ip-address "$DC2_PUBLIC_IP_NAME" \
    --private-ip-address "$DC2_PRIVATE_IP" \
    --location "$LOCATION"
fi

# =========================================================
# POINT DNS AT THE DOMAIN CONTROLLER (Azure NIC level)
# ---------------------------------------------------------
# Microsoft guidance: the preferred DNS server should be set at the Azure NIC/VNet
# level, NOT inside the guest, so it survives reboots and DHCP renewals. The DC
# points at itself; the SQL nodes point at the DC. Domain members must use AD DNS
# ONLY (never the Azure resolver as a secondary), so a single server is set. Set
# on the NIC is idempotent (re-applying the same value is a no-op).
# =========================================================

echo -e "${BLUE}Setting NIC-level DNS: DC -> self, SQL nodes -> DC ($DC_PRIVATE_IP)...${NC}"
az network nic update --resource-group "$RESOURCE_GROUP" --name "$DC_NIC_NAME"     --dns-servers "$DC_PRIVATE_IP" --output none
az network nic update --resource-group "$RESOURCE_GROUP" --name "$WIN_NIC_NAME"    --dns-servers "$DC_PRIVATE_IP" --output none
az network nic update --resource-group "$RESOURCE_GROUP" --name "$WIN_NIC_NAME_2"  --dns-servers "$DC_PRIVATE_IP" --output none
