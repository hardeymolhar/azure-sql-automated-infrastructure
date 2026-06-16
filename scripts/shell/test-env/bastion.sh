#!/bin/bash
set -euo pipefail

source "$(dirname "$0")/env.conf"

# =========================================================
# AZURE BASTION
# =========================================================
# Deploys an Azure Bastion host into the existing VNet so the Linux (RHEL) and
# Windows SQL VMs can be reached over their PRIVATE IPs - no inbound public
# SSH/RDP required. Standard SKU + tunneling is used so the native client works
# from macOS (az network bastion ssh / tunnel).
#
# Idempotent: every step checks for existing resources and skips if present.
# NOTE: the Bastion host itself takes ~5-10 minutes to provision.

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
# CREATE AZURE BASTION SUBNET
# =========================================================
# Name MUST be exactly "AzureBastionSubnet" and be /26 or larger.

if resource_exists "az network vnet subnet show --resource-group $RESOURCE_GROUP --vnet-name $VNET_NAME --name $BASTION_SUBNET_NAME"; then
  echo -e "${YELLOW}AzureBastionSubnet already exists. Skipping creation...${NC}"
else
  echo -e "${BLUE}Creating AzureBastionSubnet ($BASTION_SUBNET_PREFIX)...${NC}"

  az network vnet subnet create \
    --resource-group "$RESOURCE_GROUP" \
    --vnet-name "$VNET_NAME" \
    --name "$AZURE_BASTION_SUBNET_NAME" \
    --address-prefixes "$AZURE_BASTION_SUBNET_PREFIX"
fi

# =========================================================
# CREATE BASTION PUBLIC IP
# =========================================================
# Bastion requires a Standard SKU, statically-allocated public IP.

if resource_exists "az network public-ip show --resource-group $RESOURCE_GROUP --name $BASTION_PUBLIC_IP_NAME"; then
  echo -e "${YELLOW}Bastion Public IP already exists. Skipping creation...${NC}"
else
  echo -e "${BLUE}Creating Bastion Public IP...${NC}"

  az network public-ip create \
    --resource-group "$RESOURCE_GROUP" \
    --location "$LOCATION" \
    --name "$BASTION_PUBLIC_IP_NAME" \
    --sku Standard \
    --allocation-method Static
fi

# =========================================================
# ALLOW BASTION -> LINUX VM (SSH 22)
# =========================================================

if resource_exists "az network nsg rule show --resource-group $RESOURCE_GROUP --nsg-name $NSG_NAME --name Allow-SSH-Bastion"; then
  echo -e "${YELLOW}Linux NSG Bastion rule already exists. Skipping...${NC}"
else
  echo -e "${BLUE}Allowing SSH from Bastion subnet to Linux VM...${NC}"

  az network nsg rule create \
    --resource-group "$RESOURCE_GROUP" \
    --nsg-name "$NSG_NAME" \
    --name "Allow-SSH-Bastion" \
    --priority 1100 \
    --direction Inbound \
    --access Allow \
    --protocol Tcp \
    --source-address-prefixes "$BASTION_SUBNET_PREFIX" \
    --source-port-ranges "*" \
    --destination-port-ranges 22
fi

# =========================================================
# ALLOW BASTION -> WINDOWS VM (RDP 3389)
# =========================================================

if resource_exists "az network nsg rule show --resource-group $RESOURCE_GROUP --nsg-name $WIN_NSG_NAME --name Allow-RDP-Bastion"; then
  echo -e "${YELLOW}Windows NSG Bastion rule already exists. Skipping...${NC}"
else
  echo -e "${BLUE}Allowing RDP from Bastion subnet to Windows VM...${NC}"

  az network nsg rule create \
    --resource-group "$RESOURCE_GROUP" \
    --nsg-name "$NSG_NAME" \
    --name "Allow-RDP-Bastion" \
    --priority 1200 \
    --direction Inbound \
    --access Allow \
    --protocol Tcp \
    --source-address-prefixes "$BASTION_SUBNET_PREFIX" \
    --source-port-ranges "*" \
    --destination-port-ranges 3389
fi

# =========================================================
# CREATE BASTION HOST (Standard SKU + tunneling)
# =========================================================
# --enable-tunneling true is required for the native client (az network
# bastion ssh / tunnel) used from macOS. This step is the slow one (~5-10 min).

if resource_exists "az network bastion show --resource-group $RESOURCE_GROUP --name $BASTION_NAME"; then
  echo -e "${YELLOW}Bastion host already exists. Skipping creation...${NC}"
else
  echo -e "${BLUE}Creating Bastion host (this can take ~5-10 minutes)...${NC}"

  az network bastion create \
    --resource-group "$RESOURCE_GROUP" \
    --location "$LOCATION" \
    --name "$BASTION_NAME" \
    --vnet-name "$VNET_NAME" \
    --public-ip-address "$BASTION_PUBLIC_IP_NAME" \
    --sku "$BASTION_SKU" \
    --enable-tunneling true
fi

# =========================================================
# RESOLVE VM RESOURCE IDS (for connection commands)
# =========================================================

# LIN_VM_ID=$(az vm show \
#   --resource-group "$RESOURCE_GROUP" \
#   --name "$VM_NAME" \
#   --query id \
#   -o tsv)

WIN_VM_ID=$(az vm show \
  --resource-group "$RESOURCE_GROUP" \
  --name "$WIN_VM_NAME" \
  --query id \
  -o tsv)

# =========================================================
# CONNECTION INFO
# =========================================================

echo -e "${GREEN}==========================================${NC}"
echo -e "${GREEN}Azure Bastion deployed successfully.${NC}"
echo -e "${GREEN}==========================================${NC}"
echo -e "${GREEN}Bastion:${NC} $BASTION_NAME  (SKU: $BASTION_SKU, tunneling enabled)"
echo ""
echo -e "${GREEN}Connect to the LINUX VM (SSH) from your Mac terminal:${NC}"
echo "az network bastion ssh \\"
echo "  --name $BASTION_NAME \\"
echo "  --resource-group $RESOURCE_GROUP \\"
echo "  --target-resource-id $LIN_VM_ID \\"
echo "  --auth-type ssh-key \\"
echo "  --username $ADMIN_USERNAME \\"
echo "  --ssh-key $SSH_PRIVATE_KEY_PATH"
echo ""
echo -e "${GREEN}Connect to the WINDOWS VM (RDP) from your Mac:${NC}"
echo "# 1) Open a tunnel (leave this running):"
echo "az network bastion tunnel \\"
echo "  --name $BASTION_NAME \\"
echo "  --resource-group $RESOURCE_GROUP \\"
echo "  --target-resource-id $WIN_VM_ID \\"
echo "  --resource-port 3389 \\"
echo "  --port 13389"
echo "# 2) In Microsoft Remote Desktop, connect to:  localhost:13389"
echo "#    user: $ADMIN_USERNAME"
echo -e "${GREEN}==========================================${NC}"
