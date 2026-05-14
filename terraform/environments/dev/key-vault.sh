set -euo pipefail


source "$(dirname "$0")/env.conf"


if az keyvault show --name "$KV_NAME" >/dev/null 2>&1
then
    echo -e "${GREEN}Key Vault already exists: $KV_NAME${NC}"
else
    echo -e "${YELLOW}Creating Key Vault: $KV_NAME${NC}"

    az keyvault create \
      --name "$KV_NAME" \
      --resource-group "$RESOURCE_GROUP" \
      --location "$LOCATION" \
      --sku standard \
      --retention-days 7 \
      --enable-purge-protection true \
      --public-network-access Enabled \
      --default-action Deny \
      --enable-rbac-authorization false \
      --bypass AzureServices
fi


if az keyvault network-rule list \
    --name "$KV_NAME" \
    --query "ipRules[?value=='$CLIENT_IP']" \
    -o tsv | grep -q "$CLIENT_IP"
then
    echo -e "${GREEN}IP rule already exists: $CLIENT_IP${NC}"
else
    az keyvault network-rule add \
      --name "$KV_NAME" \
      --ip-address "$CLIENT_IP"
fi


#
if az keyvault network-rule list \
    --name "$KV_NAME" \
    --query "ipRules[?value=='$CLIENT_IP']" \
    -o tsv | grep -q "$CLIENT_IP"
then
    echo -e "${GREEN}IP rule already exists: $CLIENT_IP${NC}"
else
    az keyvault network-rule add \
      --name "$KV_NAME" \
      --ip-address "$CLIENT_IP"
fi



echo "Waiting for Key Vault DNS propagation..."

until nslookup "${KV_NAME}.vault.azure.net" >/dev/null 2>&1
do
    echo -e "${YELLOW}Key Vault endpoint not ready yet...${NC}"
    sleep 10
done

echo "Key Vault endpoint resolved successfully."



if az keyvault key show \
    --vault-name "$KV_NAME" \
    --name "column-master-key" \
    &>/dev/null
then
    echo "Key already exists: column-master-key"
else
    az keyvault key create \
      --vault-name "$KV_NAME" \
      --name "column-master-key" \
      --kty RSA \
      --size 2048 \
      --ops wrapKey unwrapKey sign verify
fi



if az keyvault key show \
    --vault-name "$KV_NAME" \
    --name "tde-encrypted-key" \
    &>/dev/null
then
    echo "Key already exists: tde-encrypted-key"
else
    az keyvault key create \
      --vault-name "$KV_NAME" \
      --name "tde-encrypted-key" \
      --kty RSA \
      --size 2048 \
      --ops wrapKey unwrapKey sign verify encrypt decrypt
fi


if az keyvault key show \
    --vault-name "$KV_NAME" \
    --name "$DISK_ENCRYPTION_SET_KEY" \
    &>/dev/null
then
    echo "Key already exists: $DISK_ENCRYPTION_SET_KEY"
else
    az keyvault key create \
      --vault-name "$KV_NAME" \
      --name "$DISK_ENCRYPTION_SET_KEY" \
      --kty RSA \
      --size 2048 \
      --ops wrapKey unwrapKey 
fi

if az keyvault secret show \
    --vault-name "$KV_NAME" \
    --name "sql-admin-password" \
    &>/dev/null
then
    echo "Secret already exists: sql-admin-password"
else
    az keyvault secret set \
      --vault-name "$KV_NAME" \
      --name "sql-admin-password" \
      --value "$ADMIN_PASSWORD"
fi

# ==========================================
# UPLOAD SSH PRIVATE KEY
# ==========================================

if az keyvault secret show \
    --vault-name "$KV_NAME" \
    --name "$PRIVATE_SSH_SECRET_NAME" \
    &>/dev/null
then
    echo "Secret already exists: $PRIVATE_SSH_SECRET_NAME"
else
    az keyvault secret set \
      --vault-name "$KV_NAME" \
      --name "$PRIVATE_SSH_SECRET_NAME" \
      --file "$SSH_PRIVATE_KEY_PATH"
fi

# ==========================================
# UPLOAD SSH PUBLIC KEY
# ==========================================

if az keyvault secret show \
    --vault-name "$KV_NAME" \
    --name "$PUBLIC_SSH_SECRET_NAME" \
    &>/dev/null
then
    echo "Secret already exists: $PUBLIC_SSH_SECRET_NAME"
else
    az keyvault secret set \
      --vault-name "$KV_NAME" \
      --name "$PUBLIC_SSH_SECRET_NAME" \
      --file "$SSH_PUBLIC_KEY_PATH"
fi



AE_KEY_ID=$(az keyvault key show \
  --vault-name $KV_NAME \
  --name column-master-key \
  --query key.kid -o tsv)


echo -e "${GREEN}Key Vault setup complete. Always Encrypted Key ID: $AE_KEY_ID${NC}"
echo -e "${GREEN}Key Vault Name: $KV_NAME${NC}"
echo -e "${GREEN}Key Vault ID: $(az keyvault show --name $KV_NAME --query id -o tsv)${NC}"







