set -euo pipefail
source "$(dirname "$0")/env.conf"


# =========================================================

# STORAGE ACCOUNT

# =========================================================

echo "=================================================="

echo "CHECK STORAGE ACCOUNT"

echo "=================================================="

if az storage account show \
    --name "$STORAGE_ACCOUNT_NAME" \
    --resource-group "$RESOURCE_GROUP" \
    >/dev/null 2>&1; then

    echo "Storage account already exists."

else

    echo "Creating storage account..."

    az storage account create \
        --name "$STORAGE_ACCOUNT_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --location "$LOCATION" \
        --sku "$STORAGE_SKU" \
        --kind StorageV2 \
        --https-only true \
        --min-tls-version "$MIN_TLS_VERSION" \
        --allow-blob-public-access false \
        --default-action "$DEFAULT_NETWORK_ACTION" \
        --allow-shared-key-access true \
        --bypass AzureServices

fi

if az storage container show \
    --name "$CONTAINER_NAME" \
    --resource-group "$RESOURCE_GROUP" \
    >/dev/null 2>&1; then

    echo "Container already exists."

else

    echo "Creating container..."
    az storage container create \
    --account-name "$STORAGE_ACCOUNT_NAME" \
    --name "$CONTAINER_NAME" \
    --public-access off

fi

if az storage container show \
    --name "$XEVENT_CONTAINER_NAME" \
    --resource-group "$RESOURCE_GROUP" \
    >/dev/null 2>&1; then

    echo "XEvent container already exists."

else

    echo "Creating XEvent container..."
    az storage container create \
    --account-name "$STORAGE_ACCOUNT_NAME" \
    --name "$XEVENT_CONTAINER_NAME" \
    --public-access off

fi

# =========================================================

# PUBLIC NETWORK ACCESS

# =========================================================

echo "=================================================="

echo "CONFIGURE PUBLIC NETWORK ACCESS"

echo "=================================================="

az storage account update \
    --name "$STORAGE_ACCOUNT_NAME" \
    --resource-group "$RESOURCE_GROUP" \
    --public-network-access Enabled \
    --bypass AzureServices

# =========================================================

# CHECK VNET

# =========================================================

echo "=================================================="

echo "CHECK VNET"

echo "=================================================="

if az network vnet show \
    --resource-group "$RESOURCE_GROUP" \
    --name "$VNET_NAME" \
    >/dev/null 2>&1; then

    echo "VNet exists."

else

    echo "ERROR: VNet does not exist."

    exit 1

fi

# =========================================================

# CHECK SUBNET

# =========================================================

echo "=================================================="

echo "CHECK SUBNET"

echo "=================================================="

if az network vnet subnet show \
    --resource-group "$RESOURCE_GROUP" \
    --vnet-name "$VNET_NAME" \
    --name "$SUBNET_NAME" \
    >/dev/null 2>&1; then

    echo "Subnet exists."

else

    echo "ERROR: Subnet does not exist."

    exit 1

fi

# =========================================================

# CHECK IP RULE

# =========================================================

echo "=================================================="
echo "CHECK IP RULE"
echo "=================================================="

existing_ip_rule=$(

    az storage account network-rule list \
        --resource-group "$RESOURCE_GROUP" \
        --account-name "$STORAGE_ACCOUNT_NAME" \
        --query "ipRules[?ipAddressOrRange=='$CLIENT_IP']" \
        -o tsv

)

if [ -n "$existing_ip_rule" ]; then

    echo "IP rule already exists."

else

    echo "Adding IP rule..."

    az storage account network-rule add \
        --resource-group "$RESOURCE_GROUP" \
        --account-name "$STORAGE_ACCOUNT_NAME" \
        --ip-address "$CLIENT_IP"

fi

# =========================================================

# CHECK VNET RULE

# =========================================================

echo "=================================================="

echo "CHECK VNET RULE"

echo "=================================================="

existing_vnet_rule=$(

    az storage account network-rule list \
        --resource-group "$RESOURCE_GROUP" \
        --account-name "$STORAGE_ACCOUNT_NAME" \
        --query "virtualNetworkRules[?contains(virtualNetworkResourceId, '$SUBNET_NAME')]" \
        -o tsv

)

if [ -n "$existing_vnet_rule" ]; then

    echo "VNet rule already exists."

else

    echo "Adding VNet rule..."

    az storage account network-rule add \
        --resource-group "$RESOURCE_GROUP" \
        --account-name "$STORAGE_ACCOUNT_NAME" \
        --vnet-name "$VNET_NAME" \
        --subnet "$SUBNET_NAME"

fi

# =========================================================

# ENABLE BLOB VERSIONING

# =========================================================

echo "=================================================="

echo "CONFIGURE BLOB VERSIONING"

echo "=================================================="

current_versioning=$(

    az storage account blob-service-properties show \
        --account-name "$STORAGE_ACCOUNT_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --query "isVersioningEnabled" \
        -o tsv

)

if [ "$current_versioning" = "true" ]; then

    echo "Blob versioning already enabled."

else

    echo "Enabling blob versioning..."

    az storage account blob-service-properties update \
        --account-name "$STORAGE_ACCOUNT_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --enable-versioning true

fi

# =========================================================

# ENABLE SOFT DELETE

# =========================================================

echo "=================================================="

echo "CONFIGURE SOFT DELETE"

echo "=================================================="

current_soft_delete=$(

    az storage account blob-service-properties show \
        --account-name "$STORAGE_ACCOUNT_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --query "deleteRetentionPolicy.enabled" \
        -o tsv

)

if [ "$current_soft_delete" = "true" ]; then

    echo "Soft delete already enabled."

else

    echo "Enabling soft delete..."

    az storage account blob-service-properties update \
        --account-name "$STORAGE_ACCOUNT_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --enable-delete-retention true \
        --delete-retention-days 14

fi


if az storage container policy show \
    --account-name "$STORAGE_ACCOUNT_NAME" \
    --container-name "$XEVENT_CONTAINER_NAME" \
    --name xevent-policy-v3 \
    >/dev/null 2>&1; then

    echo "XEvent stored access policy already exists."

else

    az storage container policy create \
        --account-name "$STORAGE_ACCOUNT_NAME" \
        --container-name "$XEVENT_CONTAINER_NAME" \
        --name xevent-policy-v3 \
        --permissions racwdl \
        --expiry 2030-12-31T23:59:00Z

fi




STORAGE_ACCOUNT_KEY=$(az storage account keys list \
    --account-name "$STORAGE_ACCOUNT_NAME" \
    --resource-group "$RESOURCE_GROUP" \
    --query "[0].value" \
    -o tsv)

SAS=$(az storage container generate-sas \
    --account-name "$STORAGE_ACCOUNT_NAME" \
    --name "$XEVENT_CONTAINER_NAME" \
    --permissions racwdl \
    --expiry 2030-12-31T23:59:00Z \
    --https-only \
    --account-key "$STORAGE_ACCOUNT_KEY" \
    -o tsv)
