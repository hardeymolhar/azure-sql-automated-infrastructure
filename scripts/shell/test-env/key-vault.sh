set -euo pipefail

RESOURCE_GROUP=$(az group list --query "[1].name" -o tsv)
LOCATION="eastus"



SSH_PRIVATE_KEY_PATH="/Users/mac/.ssh/ssh_key/vm-key/vm-key"
SSH_PUBLIC_KEY_PATH="/Users/mac/.ssh/ssh_key/vm-key/vm-key.pub"

KV_NAME="kv-2348112"



CLIENT_IP=$(curl -s https://api.ipify.org)

TENANT_ID=$(az account show --query tenantId -o tsv)

MY_OBJECT_ID=$(az ad signed-in-user show --query id -o tsv)




if az keyvault show --name "$KV_NAME" >/dev/null 2>&1
then
    echo "Key Vault already exists: $KV_NAME"
else
    echo "Creating Key Vault: $KV_NAME"

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
    echo "IP rule already exists: $CLIENT_IP"
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
    echo "IP rule already exists: $CLIENT_IP"
else
    az keyvault network-rule add \
      --name "$KV_NAME" \
      --ip-address "$CLIENT_IP"
fi



echo "Waiting for Key Vault DNS propagation..."

until nslookup "${KV_NAME}.vault.azure.net" >/dev/null 2>&1
do
    echo "Key Vault endpoint not ready yet..."
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
# ==========================================
# UPLOAD SSH PRIVATE KEY
# ==========================================

if az keyvault secret show \
    --vault-name "$KV_NAME" \
    --name "vm-ssh-private-key" \
    &>/dev/null
then
    echo "Secret already exists: vm-ssh-private-key"
else
    az keyvault secret set \
      --vault-name "$KV_NAME" \
      --name "vm-ssh-private-key" \
      --file "$SSH_PRIVATE_KEY_PATH"
fi

# ==========================================
# UPLOAD SSH PUBLIC KEY
# ==========================================

if az keyvault secret show \
    --vault-name "$KV_NAME" \
    --name "vm-ssh-public-key" \
    &>/dev/null
then
    echo "Secret already exists: vm-ssh-public-key"
else
    az keyvault secret set \
      --vault-name "$KV_NAME" \
      --name "vm-ssh-public-key" \
      --file "$SSH_PUBLIC_KEY_PATH"
fi



AE_KEY_ID=$(az keyvault key show \
  --vault-name $KV_NAME \
  --name column-master-key \
  --query key.kid -o tsv)


echo "Key Vault setup complete. Always Encrypted Key ID: $AE_KEY_ID"
echo "Key Vault Name: $KV_NAME"
echo "Key Vault ID: $(az keyvault show --name $KV_NAME --query id -o tsv)"







