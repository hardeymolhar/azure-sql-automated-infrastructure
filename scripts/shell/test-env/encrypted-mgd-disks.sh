
#!/bin/bash
set -euo pipefail

source "$(dirname "$0")/env.conf"


KV_NAME="$(az keyvault list --resource-group "$RESOURCE_GROUP" --query "[?contains(name, '$RESOURCE_SUFFIX')].name | [0]" -o tsv)"
SUBSCRIPTION_ID="$(az account show --query id -o tsv)"

DISK_ENCRYPTION_KEY_URL=$(az keyvault key show \
  --vault-name $KV_NAME \
  --name $DISK_ENCRYPTION_SET_KEY \
  --query key.kid \
  -o tsv)

echo -e "${YELLOW}Retrieved key URL: $DISK_ENCRYPTION_KEY_URL${NC}"


echo -e "${YELLOW}Creating disk encryption set...${NC}"

az disk-encryption-set create \
  --name $DES_NAME \
  --resource-group $RESOURCE_GROUP \
  --location $LOCATION \
  --source-vault "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.KeyVault/vaults/$KV_NAME" \
  --key-url $DISK_ENCRYPTION_KEY_URL


DES_PRINCIPAL_ID=$(az disk-encryption-set show \
  --name $DES_NAME \
  --resource-group $RESOURCE_GROUP \
  --query identity.principalId \
  -o tsv)

echo -e "${GREEN}Retrieved disk encryption set principal ID: $DES_PRINCIPAL_ID${NC}"


az keyvault set-policy \
  --name $KV_NAME \
  --object-id $DES_PRINCIPAL_ID \
  --key-permissions get wrapKey unwrapKey


echo -e "${YELLOW}Creating managed disks...${NC}"
az disk create \
  --resource-group $RESOURCE_GROUP \
  --name $DATA_DISK \
  --location $LOCATION \
  --size-gb 4096 \
  --sku StandardSSD_LRS \
  --disk-encryption-set "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.Compute/diskEncryptionSets/$DES_NAME"

az disk create \
  --resource-group $RESOURCE_GROUP \
  --name $LOG_DISK \
  --location $LOCATION \
  --size-gb 4096 \
  --sku StandardSSD_LRS \
  --disk-encryption-set "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.Compute/diskEncryptionSets/$DES_NAME"


az disk create \
  --resource-group $RESOURCE_GROUP \
  --name $TEMP_DISK \
  --location $LOCATION \
  --size-gb 4096 \
  --sku StandardSSD_LRS \
  --disk-encryption-set "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.Compute/diskEncryptionSets/$DES_NAME"


az disk create \
  --resource-group $RESOURCE_GROUP \
  --name $BACKUP_DISK \
  --location $LOCATION \
  --size-gb 4096 \
  --sku StandardSSD_LRS \
  --disk-encryption-set "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.Compute/diskEncryptionSets/$DES_NAME"       


echo -e "${GREEN}Encrypted managed disks created successfully.${NC}"