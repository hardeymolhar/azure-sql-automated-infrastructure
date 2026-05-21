#!/bin/bash
source "$(dirname "$0")/env.conf"
set -euo pipefail



KV_NAME=$(az keyvault list \
  --resource-group "$RESOURCE_GROUP" \
  --query "[?contains(name, '$RESOURCE_SUFFIX')].name | [0]" \
  -o tsv)

# ==========================================
# FETCH PUBLIC SSH KEY FROM KEY VAULT
# ==========================================

SSH_PUBLIC_KEY=$(az keyvault secret show \
  --vault-name "$KV_NAME" \
  --name "$SSH_SECRET_NAME" \
  --query value \
  -o tsv)


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
    --public-ip-address "$PUBLIC_IP_NAME"
fi

# =========================================================
# CREATE VM
# =========================================================

if resource_exists "az vm show --resource-group $RESOURCE_GROUP --name $VM_NAME"; then
  echo -e "${YELLOW}VM already exists. Skipping creation...${NC}"
else
  echo -e "${BLUE}Creating VM...${NC}"

  az vm create \
    --resource-group "$RESOURCE_GROUP" \
    --location "$LOCATION" \
    --name "$VM_NAME" \
    --nics "$NIC_NAME" \
    --image "$IMAGE" \
    --size "$VM_SIZE" \
    --admin-username "$ADMIN_USERNAME" \
    --ssh-key-values "$SSH_PUBLIC_KEY_PATH" \
    --os-disk-name "$OS_DISK" \
    --os-disk-size-gb 512 \
    --storage-sku StandardSSD_LRS \
    --assign-identity
fi

# =========================================================
# ATTACH DATA DISK
# =========================================================

DATA_DISK_ID=$(az disk show \
  --resource-group "$RESOURCE_GROUP" \
  --name "$DATA_DISK" \
  --query id \
  -o tsv)

if az vm show \
    --resource-group "$RESOURCE_GROUP" \
    --name "$VM_NAME" \
    --query "storageProfile.dataDisks[?name=='$DATA_DISK']" \
    -o tsv | grep -q "$DATA_DISK"; then

  echo -e "${YELLOW}DATA disk already attached. Skipping...${NC}"

else

  echo -e "${BLUE}Attaching DATA disk...${NC}"

  az vm disk attach \
    --resource-group "$RESOURCE_GROUP" \
    --vm-name "$VM_NAME" \
    --ids "$DATA_DISK_ID" \
    --lun 0

  echo -e "${GREEN}DATA disk attached successfully.${NC}"
fi

# =========================================================
# ATTACH LOG DISK
# =========================================================
LOG_DISK_ID=$(az disk show \
  --resource-group "$RESOURCE_GROUP" \
  --name "$LOG_DISK" \
  --query id \
  -o tsv)

if az vm show \
    --resource-group "$RESOURCE_GROUP" \
    --name "$VM_NAME" \
    --query "storageProfile.dataDisks[?name=='$LOG_DISK']" \
    -o tsv | grep -q "$LOG_DISK"; then

  echo -e "${YELLOW}LOG disk already attached. Skipping...${NC}"

else

  echo -e "${BLUE}Attaching LOG disk...${NC}"

  az vm disk attach \
    --resource-group "$RESOURCE_GROUP" \
    --vm-name "$VM_NAME" \
    --name "$LOG_DISK" \
    --lun 1

  echo -e "${GREEN}LOG disk attached successfully.${NC}"
fi

# =========================================================
# ATTACH TEMP DISK
# =========================================================

TEMP_DISK_ID=$(az disk show \
  --resource-group "$RESOURCE_GROUP" \
  --name "$TEMP_DISK" \
  --query id \
  -o tsv)

if az vm show \
    --resource-group "$RESOURCE_GROUP" \
    --name "$VM_NAME" \
    --query "storageProfile.dataDisks[?name=='$TEMP_DISK']" \
    -o tsv | grep -q "$TEMP_DISK"; then

  echo -e "${YELLOW}TEMP disk already attached. Skipping...${NC}"

else

  echo -e "${BLUE}Attaching TEMP disk...${NC}"

  az vm disk attach \
    --resource-group "$RESOURCE_GROUP" \
    --vm-name "$VM_NAME" \
    --name "$TEMP_DISK" \
    --lun 2

  echo -e "${GREEN}TEMP disk attached successfully.${NC}"
fi

# =========================================================
# ATTACH BACKUP DISK
# =========================================================

BACKUP_DISK_ID=$(az disk show \
  --resource-group "$RESOURCE_GROUP" \
  --name "$BACKUP_DISK" \
  --query id \
  -o tsv)

if az vm show \
    --resource-group "$RESOURCE_GROUP" \
    --name "$VM_NAME" \
    --query "storageProfile.dataDisks[?name=='$BACKUP_DISK']" \
    -o tsv | grep -q "$BACKUP_DISK"; then

  echo -e "${YELLOW}BACKUP disk already attached. Skipping...${NC}"

else

  echo -e "${BLUE}Attaching BACKUP disk...${NC}"

  az vm disk attach \
    --resource-group "$RESOURCE_GROUP" \
    --vm-name "$VM_NAME" \
    --name "$BACKUP_DISK" \
    --lun 3

  echo -e "${GREEN}BACKUP disk attached successfully.${NC}"
fi

# =========================================================
# FETCH VM PUBLIC IP
# =========================================================


VM_PUBLIC_IP=$(az vm show \
  --resource-group "$RESOURCE_GROUP" \
  --name "$VM_NAME" \
  -d \
  --query publicIps \
  -o tsv)

# =========================================================
# ADD VM IP TO KEY VAULT NETWORK RULES
# =========================================================

if az keyvault network-rule list \
  --name "$KV_NAME" \
  --query "ipRules[?value=='$VM_PUBLIC_IP']" \
  -o tsv | grep -q "$VM_PUBLIC_IP"; then

  echo -e "${YELLOW}VM IP already exists in Key Vault network rules.${NC}"
else
  echo -e "${BLUE}Adding VM IP to Key Vault network rules...${NC}"

  az keyvault network-rule add \
    --name "$KV_NAME" \
    --ip-address "$VM_PUBLIC_IP"
fi

# =========================================================
# GET VM MANAGED IDENTITY PRINCIPAL ID
# =========================================================

MI_PRINCIPAL_ID=$(az vm identity show \
  --resource-group "$RESOURCE_GROUP" \
  --name "$VM_NAME" \
  --query principalId \
  -o tsv)

echo -e "${GREEN}Managed Identity Principal ID:${NC} $MI_PRINCIPAL_ID"

# =========================================================
# KEY VAULT ACCESS POLICY - SECRETS
# =========================================================

echo -e "${BLUE}Assigning secret permissions to VM managed identity...${NC}"

az keyvault set-policy \
  --name "$KV_NAME" \
  --object-id "$MI_PRINCIPAL_ID" \
  --secret-permissions get list

# =========================================================
# KEY VAULT ACCESS POLICY - KEYS
# =========================================================

echo -e "${BLUE}Assigning key permissions to VM managed identity...${NC}"

az keyvault set-policy \
  --name "$KV_NAME" \
  --object-id "$MI_PRINCIPAL_ID" \
  --key-permissions get wrapKey unwrapKey list

# =========================================================
# VALIDATION
# =========================================================

echo -e "${GREEN}==========================================${NC}"
echo -e "${GREEN}VM deployed successfully.${NC}"
echo -e "${GREEN}==========================================${NC}"
echo -e "${GREEN}VM Name:${NC} $VM_NAME"
echo -e "${GREEN}Public IP:${NC} $VM_PUBLIC_IP"
echo ""
echo -e "${GREEN}SSH Command:${NC}"
echo -e "ssh -i /Users/mac/.ssh/ssh_key/vm_name/vm_name $ADMIN_USERNAME@$VM_PUBLIC_IP"
echo -e "${GREEN}==========================================${NC}"
