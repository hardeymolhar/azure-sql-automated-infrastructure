#!/bin/bash
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
        --default-action Allow \
        --public-network-access "$PUBLIC_NETWORK_ACCESS" \
        --allow-shared-key-access true \
        --bypass AzureServices
    # Created OPEN (default-action Allow) so the control-node data-plane calls
    # below succeed; locked to $DEFAULT_NETWORK_ACTION as the final step.

fi

# =========================================================
# RETRIEVE ACCOUNT KEY (used by every data-plane call below)
# =========================================================
# Fetched once, right after the account is ensured, so the container/policy
# operations authenticate with the key consistently (no reliance on AAD
# data-plane RBAC, which the sandbox user may not hold).
STORAGE_ACCOUNT_KEY=$(az storage account keys list \
    --account-name "$STORAGE_ACCOUNT_NAME" \
    --resource-group "$RESOURCE_GROUP" \
    --query "[0].value" \
    -o tsv)

if [ -z "$STORAGE_ACCOUNT_KEY" ]; then
    echo "ERROR: could not retrieve the primary key for $STORAGE_ACCOUNT_NAME." >&2
    exit 1
fi

# =========================================================
# OPEN THE FIREWALL FOR PROVISIONING
# ---------------------------------------------------------
# The container/policy operations below are control-node DATA-PLANE calls, which
# the storage firewall blocks unless default-action is Allow. Open it now and
# re-lock to $DEFAULT_NETWORK_ACTION as the FINAL step. Fresh accounts were just
# created with Allow, so this only acts (and waits) when re-running against an
# account that is already locked down. The 'show'/'update' here are control-plane
# (ARM) calls, so they are not themselves subject to the data-plane firewall.
# =========================================================
current_action=$(az storage account show \
    --name "$STORAGE_ACCOUNT_NAME" \
    --resource-group "$RESOURCE_GROUP" \
    --query "networkRuleSet.defaultAction" \
    -o tsv)

if [ "$current_action" = "Deny" ]; then
    echo "Opening storage firewall for provisioning..."
    az storage account update \
        --name "$STORAGE_ACCOUNT_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --default-action Allow \
        --public-network-access "$PUBLIC_NETWORK_ACCESS" \
        --output none
    echo "Waiting up to 60s for the firewall change to propagate (Azure: 'up to a minute')..."
    sleep 60
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



if az storage container show \
    --name "$CONTAINER_NAME" \
    --account-name "$STORAGE_ACCOUNT_NAME" \
    --account-key "$STORAGE_ACCOUNT_KEY" \
    >/dev/null 2>&1; then

    echo "Container already exists."

else

    echo "Creating container..."
    az storage container create \
    --account-name "$STORAGE_ACCOUNT_NAME" \
    --name "$CONTAINER_NAME" \
    --account-key "$STORAGE_ACCOUNT_KEY" \
    --public-access off

fi

# =========================================================
# UPLOAD THE DP-300 LAB ARCHIVE (account key) -> sqlbackups
# =========================================================
# Upload with the storage account key (no SAS needed to write). The Windows VMs
# later DOWNLOAD this blob via a short-lived SAS minted in vm-stg-ind-49.sh and
# passed to the Ansible playbook. --overwrite keeps re-runs idempotent.
# (STORAGE_ACCOUNT_KEY was retrieved right after the account was ensured, above.)
if [ ! -f "$LOCAL_FILE_PATH" ]; then
    echo "ERROR: upload file not found: $LOCAL_FILE_PATH" >&2
    exit 1
fi

echo "Uploading $BLOB_NAME to container $CONTAINER_NAME ..."
az storage blob upload \
    --account-name "$STORAGE_ACCOUNT_NAME" \
    --container-name "$CONTAINER_NAME" \
    --name "$BLOB_NAME" \
    --file "$LOCAL_FILE_PATH" \
    --account-key "$STORAGE_ACCOUNT_KEY" \
    --overwrite

if az storage container show \
    --name "$XEVENT_CONTAINER_NAME" \
    --account-name "$STORAGE_ACCOUNT_NAME" \
    --account-key "$STORAGE_ACCOUNT_KEY" \
    >/dev/null 2>&1; then

    echo "XEvent container already exists."

else

    echo "Creating XEvent container..."
    az storage container create \
    --account-name "$STORAGE_ACCOUNT_NAME" \
    --name "$XEVENT_CONTAINER_NAME" \
    --account-key "$STORAGE_ACCOUNT_KEY" \
    --public-access off

fi

# =========================================================
# CHECK VNET RULES
# ---------------------------------------------------------
# Allow both subnets so the Linux VM (SUBNET_NAME) and the Windows SQL cluster
# nodes (WIN_SUBNET_NAME) can reach the storage account. The Windows subnet rule
# is required for Cloud Witness: WSFC nodes call Azure Blob from inside the VNet.
# Prerequisite: each subnet must have the Microsoft.Storage service endpoint
# enabled (network.sh adds it to WIN_SUBNET_NAME; SUBNET_NAME already had it).
# =========================================================
echo "=================================================="
echo "CHECK VNET RULES"
echo "=================================================="

for SUBNET in "$WIN_SUBNET_NAME" "$SUBNET_NAME"; do
    existing_vnet_rule=$(
        az storage account network-rule list \
            --resource-group "$RESOURCE_GROUP" \
            --account-name "$STORAGE_ACCOUNT_NAME" \
            --query "virtualNetworkRules[?contains(virtualNetworkResourceId, '${SUBNET}')]" \
            -o tsv
    )
    if [ -n "$existing_vnet_rule" ]; then
        echo "VNet rule already exists for subnet $SUBNET."
    else
        echo "Adding VNet rule for subnet $SUBNET..."
        az storage account network-rule add \
            --resource-group "$RESOURCE_GROUP" \
            --account-name "$STORAGE_ACCOUNT_NAME" \
            --vnet-name "$VNET_NAME" \
            --subnet "$SUBNET"
    fi
done

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
    --account-key "$STORAGE_ACCOUNT_KEY" \
    >/dev/null 2>&1; then

    echo "XEvent stored access policy already exists."

else

    az storage container policy create \
        --account-name "$STORAGE_ACCOUNT_NAME" \
        --container-name "$XEVENT_CONTAINER_NAME" \
        --name xevent-policy-v3 \
        --permissions racwdl \
        --expiry 2030-12-31T23:59:00Z \
        --account-key "$STORAGE_ACCOUNT_KEY"

fi




# The XEvent stored access policy above is the deliverable here. The SAS the
# XEvent database-scoped credential needs is minted where it is consumed, in
# identity.sh — not here — so no SAS is generated in this script.

# =========================================================
# LOCK DOWN THE FIREWALL (FINAL STEP)
# ---------------------------------------------------------
# All data-plane provisioning is done and the IP + VNet rules are registered, so
# switch default-action to $DEFAULT_NETWORK_ACTION now. End-state: public network
# access Enabled, but reachable only from the client IP, the VM subnets, and
# trusted Azure services ("reachable but firewalled").
# =========================================================
echo "=================================================="
echo "LOCK DOWN STORAGE FIREWALL ($DEFAULT_NETWORK_ACTION)"
echo "=================================================="

az storage account update \
    --name "$STORAGE_ACCOUNT_NAME" \
    --resource-group "$RESOURCE_GROUP" \
    --public-network-access "$PUBLIC_NETWORK_ACCESS" \
    --default-action "$DEFAULT_NETWORK_ACTION" \
    --bypass AzureServices \
    --output none
