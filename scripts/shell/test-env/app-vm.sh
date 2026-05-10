#!/bin/bash

set -euo pipefail

# =========
# VARIABLES
# =========

RESOURCE_GROUP="$(az group list --query "[1].name" -o tsv)"
LOCATION="$(az group list --query "[1].location" -o tsv)"

VM_NAME="vm-2348O1"
VNET_NAME="vnet-2348O1"
SUBNET_NAME="subnet-2348O1"
NSG_NAME="nsg-2348O1"
NIC_NAME="nic-2348O1"
PUBLIC_IP_NAME="pip-2348O1"

KV_NAME=$(az keyvault list \
  --resource-group "$RESOURCE_GROUP" \
  --query "[?contains(name, '-2348O1')].name | [0]" \
  -o tsv)

SSH_SECRET_NAME="vm-ssh-public-key"
ADMIN_USERNAME="sqladmin"
VM_SIZE="Standard_B2ms"
IMAGE="RedHat:RHEL:9-lvm-gen2:latest"

# ==========================================
# GET CLIENT PUBLIC IP
# ==========================================

CLIENT_IP=$(curl -s ifconfig.me)
echo "Client Public IP: $CLIENT_IP"

# ==========================================
# FETCH PUBLIC SSH KEY FROM KEY VAULT
# ==========================================

SSH_PUBLIC_KEY=$(az keyvault secret show \
  --vault-name "$KV_NAME" \
  --name "$SSH_SECRET_NAME" \
  --query value \
  -o tsv)

# ==========================================
# CREATE VNET
# ==========================================

az network vnet create \
  --resource-group "$RESOURCE_GROUP" \
  --location "$LOCATION" \
  --name "$VNET_NAME" \
  --subnet-name "$SUBNET_NAME"

# ==========================================
# CREATE NSG
# ==========================================

az network nsg create \
  --resource-group "$RESOURCE_GROUP" \
  --location "$LOCATION" \
  --name "$NSG_NAME"

# ==========================================
# ALLOW SSH ONLY FROM CLIENT IP
# ==========================================

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

# ==========================================
# CREATE PUBLIC IP
# ==========================================

az network public-ip create \
  --resource-group "$RESOURCE_GROUP" \
  --location "$LOCATION" \
  --name "$PUBLIC_IP_NAME" \
  --sku Standard

# ==========================================
# CREATE NIC
# ==========================================

az network nic create \
  --resource-group "$RESOURCE_GROUP" \
  --name "$NIC_NAME" \
  --vnet-name "$VNET_NAME" \
  --subnet "$SUBNET_NAME" \
  --network-security-group "$NSG_NAME" \
  --public-ip-address "$PUBLIC_IP_NAME"

# ==========================================
# CREATE VM
# ==========================================

az vm create \
  --resource-group "$RESOURCE_GROUP" \
  --location "$LOCATION" \
  --name "$VM_NAME" \
  --nics "$NIC_NAME" \
  --image "$IMAGE" \
  --size "$VM_SIZE" \
  --admin-username "$ADMIN_USERNAME" \
  --ssh-key-values "$SSH_PUBLIC_KEY" \
  --assign-identity


# ==========================================
# FETCH VM PUBLIC IP
# ==========================================

VM_PUBLIC_IP=$(az vm show \
  --resource-group "$RESOURCE_GROUP" \
  --name "$VM_NAME" \
  -d \
  --query publicIps \
  -o tsv)


az keyvault network-rule add \
  --name "$KV_NAME" \
  --ip-address "$VM_PUBLIC_IP"



# ==========================================
# GET VM MANAGED IDENTITY PRINCIPAL ID
# ==========================================

MI_PRINCIPAL_ID=$(az vm identity show \
  --resource-group "$RESOURCE_GROUP" \
  --name "$VM_NAME" \
  --query principalId \
  -o tsv)

echo "Managed Identity Principal ID: $MI_PRINCIPAL_ID"

# ==========================================
# KEY VAULT ACCESS POLICY
# ==========================================

echo "Granting Key Vault access policy..."
az keyvault set-policy \
  --name "$KV_NAME" \
  --object-id "$MI_PRINCIPAL_ID" \
  --secret-permissions get list 


echo "Granting Key Vault access policy..."
az keyvault set-policy \
  --name "$KV_NAME" \
  --object-id "$MI_PRINCIPAL_ID" \
  --key-permissions get wrapKey unwrapKey list



echo "=========================================="
echo "VM deployed successfully."
echo "=========================================="
echo "VM Name: $VM_NAME"
echo "Public IP: $VM_PUBLIC_IP"
echo ""
echo "SSH Command:"
echo "ssh -i /Users/mac/.ssh/ssh_key/vm-key/vm-key $ADMIN_USERNAME@$VM_PUBLIC_IP"
echo "=========================================="