set -euo pipefail

RESOURCE_GROUP=$(az group list --query "[1].name" -o tsv)
LOCATION="eastus"


#GitBash
SSH_PRIVATE_KEY_PATH="/c/Users/P10822/.ssh/vm-key"
SSH_PUBLIC_KEY_PATH="/c/Users/P10822/.ssh/vm-key.pub"


# SSH_PRIVATE_KEY_PATH="/Users/mac/.ssh/ssh_key/vm-key/vm-key"
# SSH_PUBLIC_KEY_PATH="/Users/mac/.ssh/ssh_key/vm-key/vm-key.pub"
KV_NAME="kv-$RANDOM"



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
      --default-action Allow \
      --enable-rbac-authorization false
fi

az keyvault network-rule add \
  --name "$KV_NAME" \
  --ip-address "$CLIENT_IP"





az keyvault set-policy \
  --name $KV_NAME \
  --object-id $MY_OBJECT_ID \
  --key-permissions \
    get list create update delete recover backup restore \
    wrapKey unwrapKey encrypt decrypt sign verify purge release \
    rotate getrotationpolicy setrotationpolicy \
  --secret-permissions \
    get list set delete recover backup restore purge \
  --certificate-permissions \
    get list create update delete recover backup restore purge

echo "Waiting for Key Vault DNS propagation..."

until nslookup "${KV_NAME}.vault.azure.net" >/dev/null 2>&1
do
    echo "Key Vault endpoint not ready yet..."
    sleep 10
done

echo "Key Vault endpoint resolved successfully."

az keyvault key create \
  --vault-name $KV_NAME \
  --name always-encrypted-key \
  --kty RSA \
  --size 2048 \
  --ops wrapKey unwrapKey sign verify

az keyvault key create \
  --vault-name $KV_NAME \
  --name tde-encrypted-key \
  --kty RSA \
  --size 2048 \
  --ops wrapKey unwrapKey sign verify encrypt decrypt

# ==========================================
# UPLOAD SSH PRIVATE KEY
# ==========================================

az keyvault secret set \
  --vault-name "$KV_NAME" \
  --name "vm-ssh-private-key" \
  --file "$SSH_PRIVATE_KEY_PATH"

# ==========================================
# UPLOAD SSH PUBLIC KEY
# ==========================================

az keyvault secret set \
  --vault-name "$KV_NAME" \
  --name "vm-ssh-public-key" \
  --file "$SSH_PUBLIC_KEY_PATH"



AE_KEY_ID=$(az keyvault key show \
  --vault-name $KV_NAME \
  --name always-encrypted-key \
  --query key.kid -o tsv)






