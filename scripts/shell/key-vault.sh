set -euo pipefail

RESOURCE_GROUP=$(az group list --query "[1].name" -o tsv)
LOCATION="eastus"

KV_NAME="kv-$RANDOM"

SQL_SERVER_NAME="$(
  az sql server list \
    --resource-group "$RESOURCE_GROUP" \
    --query "[0].name" \
    -o tsv)"    

echo $SQL_SERVER_NAME

CLIENT_IP=$(curl -s https://api.ipify.org)

TENANT_ID=$(az account show --query tenantId -o tsv)

MY_OBJECT_ID=$(az ad signed-in-user show --query id -o tsv)


SQL_MI=$(az sql server show \
  --name $SQL_SERVER_NAME \
  --resource-group $RESOURCE_GROUP \
  --query identity.principalId -o tsv)



az keyvault create \
  --name $KV_NAME \
  --resource-group $RESOURCE_GROUP \
  --location $LOCATION \
  --sku standard \
  --retention-days 7 \
  --enable-purge-protection true \
  --public-network-access Enabled \
  --default-action Allow \
  --enable-rbac-authorization false

az keyvault set-policy \
  --name $KV_NAME \
  --object-id $SQL_MI \
  --key-permissions get wrapKey unwrapKey


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

AE_KEY_ID=$(az keyvault key show \
  --vault-name $KV_NAME \
  --name always-encrypted-key \
  --query key.kid -o tsv)

TDE_KEY_ID=$(az keyvault key show \
  --vault-name $KV_NAME \
  --name tde-encrypted-key \
  --query key.kid -o tsv)

az sql server key create \
  --server "$SQL_SERVER_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --kid "$TDE_KEY_ID"

az sql server tde-key set \
  --server "$SQL_SERVER_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --server-key-type AzureKeyVault \
  --kid "$TDE_KEY_ID"

