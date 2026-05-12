
#!/bin/bash
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

DATA_DISK="prd-rhel-db-data-01"  
LOG_DISK="prd-rhel-db-log-01"
TEMP_DISK="prd-rhel-db-temp-01"
BACKUP_DISK="prd-rhel-db-backup-01"
LOCATION="centralindia"
KEY_NAME="dess-encrypted-key"
RG="$(az group list --query "[1].name" -o tsv)"

KV_NAME="$(az keyvault list --resource-group "$RG" --query "[?contains(name, '-99999990')].name | [0]" -o tsv)"
DES_NAME="sql-des-99999990"
SUBSCRIPTION_ID="$(az account show --query id -o tsv)"

KEY_URL=$(az keyvault key show \
  --vault-name $KV_NAME \
  --name $KEY_NAME \
  --query key.kid \
  -o tsv)

echo -e "${YELLOW}Retrieved key URL: $KEY_URL${NC}"


echo -e "${YELLOW}Creating disk encryption set...${NC}"

az disk-encryption-set create \
  --name $DES_NAME \
  --resource-group $RG \
  --location $LOCATION \
  --source-vault "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RG/providers/Microsoft.KeyVault/vaults/$KV_NAME" \
  --key-url $KEY_URL


DES_PRINCIPAL_ID=$(az disk-encryption-set show \
  --name $DES_NAME \
  --resource-group $RG \
  --query identity.principalId \
  -o tsv)

echo -e "${GREEN}Retrieved disk encryption set principal ID: $DES_PRINCIPAL_ID${NC}"


az keyvault set-policy \
  --name $KV_NAME \
  --object-id $DES_PRINCIPAL_ID \
  --key-permissions get wrapKey unwrapKey


echo -e "${YELLOW}Creating managed disks...${NC}"
az disk create \
  --resource-group $RG \
  --name $DATA_DISK \
  --location $LOCATION \
  --size-gb 4096 \
  --sku StandardSSD_LRS \
  --disk-encryption-set "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RG/providers/Microsoft.Compute/diskEncryptionSets/$DES_NAME"

az disk create \
  --resource-group $RG \
  --name $LOG_DISK \
  --location $LOCATION \
  --size-gb 4096 \
  --sku StandardSSD_LRS \
  --disk-encryption-set "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RG/providers/Microsoft.Compute/diskEncryptionSets/$DES_NAME"


az disk create \
  --resource-group $RG \
  --name $TEMP_DISK \
  --location $LOCATION \
  --size-gb 4096 \
  --sku StandardSSD_LRS \
  --disk-encryption-set "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RG/providers/Microsoft.Compute/diskEncryptionSets/$DES_NAME"


az disk create \
  --resource-group $RG \
  --name $BACKUP_DISK \
  --location $LOCATION \
  --size-gb 4096 \
  --sku StandardSSD_LRS \
  --disk-encryption-set "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RG/providers/Microsoft.Compute/diskEncryptionSets/$DES_NAME"       


echo -e "${GREEN}Encrypted managed disks created successfully.${NC}"