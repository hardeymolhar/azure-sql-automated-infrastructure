#!/bin/bash

set -euo pipefail

# =========================================================
# VARIABLES
# =========================================================

RESOURCE_GROUP=$(az group list --query "[1].name" -o tsv)

LOCATION=$(az group show \
  --name "$RESOURCE_GROUP" \
  --query "location" -o tsv)

SERVER_NAME="sqlserver-2348o1"

DB_NAME="demo-db"

ADMIN_USER="sqladmin"

ADMIN_PASSWORD="R3P1IKA5X_123"

FIREWALL_RULE_NAME="AllowMyIP"

VM_FIREWALL_RULE_NAME="AllowVMIP"

VM_IP=$(az vm list-ip-addresses \
  --resource-group "$RESOURCE_GROUP" \
  --name "vm-2348o1" \
  --query "[0].virtualMachine.network.publicIpAddresses[0].ipAddress" \
  -o tsv)

KV_NAME=$(az keyvault list \
  --resource-group "$RESOURCE_GROUP" \
  --query "[?contains(name, '-2348o1')].name | [0]" \
  -o tsv)

TDE_KEY_ID=$(az keyvault key show \
  --vault-name "$KV_NAME" \
  --name tde-encrypted-key \
  --query key.kid -o tsv)

# =========================================================
# VALIDATE RESOURCE GROUP
# =========================================================

if ! az group exists --name "$RESOURCE_GROUP" | grep -q true
then
    echo "ERROR: Resource group does not exist"
    exit 1
fi

# =========================================================
# GET CLIENT PUBLIC IP
# =========================================================

MY_IP=$(curl -s https://api.ipify.org)

if [[ -z "$MY_IP" ]]
then
    echo "ERROR: Failed to retrieve public IP"
    exit 1
fi

# =========================================================
# STEP 1 — CREATE SQL SERVER
# =========================================================

echo "Creating Azure SQL logical server..."

if az sql server show \
    --name "$SERVER_NAME" \
    --resource-group "$RESOURCE_GROUP" \
    &>/dev/null
then

    echo "SQL Server exists: $SERVER_NAME"

else

    az sql server create \
        --name "$SERVER_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --location "$LOCATION" \
        --admin-user "$ADMIN_USER" \
        --admin-password "$ADMIN_PASSWORD" \
        --assign-identity

fi

# =========================================================
# STEP 2 — CREATE FIREWALL RULES
# =========================================================

echo "Creating firewall rules..."

if az sql server firewall-rule show \
    --resource-group "$RESOURCE_GROUP" \
    --server "$SERVER_NAME" \
    --name "$FIREWALL_RULE_NAME" \
    &>/dev/null
then

    echo "Client firewall rule exists"

else

    az sql server firewall-rule create \
        --resource-group "$RESOURCE_GROUP" \
        --server "$SERVER_NAME" \
        --name "$FIREWALL_RULE_NAME" \
        --start-ip-address "$MY_IP" \
        --end-ip-address "$MY_IP"

fi

if az sql server firewall-rule show \
    --resource-group "$RESOURCE_GROUP" \
    --server "$SERVER_NAME" \
    --name "$VM_FIREWALL_RULE_NAME" \
    &>/dev/null
then

    echo "VM firewall rule exists"

else

    az sql server firewall-rule create \
        --resource-group "$RESOURCE_GROUP" \
        --server "$SERVER_NAME" \
        --name "$VM_FIREWALL_RULE_NAME" \
        --start-ip-address "$VM_IP" \
        --end-ip-address "$VM_IP"

fi

# =========================================================
# STEP 3 — CREATE DATABASE
# =========================================================

echo "Creating database..."

if az sql db show \
    --resource-group "$RESOURCE_GROUP" \
    --server "$SERVER_NAME" \
    --name "$DB_NAME" \
    &>/dev/null
then

    echo "Database exists: $DB_NAME"

else

    az sql db create \
        --resource-group "$RESOURCE_GROUP" \
        --server "$SERVER_NAME" \
        --name "$DB_NAME" \
        --edition Basic \
        --max-size 2GB

fi

# =========================================================
# STEP 4 — GET SQL MANAGED IDENTITY
# =========================================================

SQL_MI=$(az sql server show \
  --name "$SERVER_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --query identity.principalId \
  -o tsv)

# =========================================================
# STEP 5 — CONFIGURE KEY VAULT POLICY
# =========================================================

POLICY_EXISTS=$(az keyvault show \
  --name "$KV_NAME" \
  --query "properties.accessPolicies[?objectId=='$SQL_MI'].objectId | [0]" \
  -o tsv)

if [[ "$POLICY_EXISTS" == "$SQL_MI" ]]
then

    echo "Key Vault policy exists"

else

    az keyvault set-policy \
      --name "$KV_NAME" \
      --object-id "$SQL_MI" \
      --key-permissions get WrapKey UnwrapKey

fi

echo "Waiting for Key Vault propagation..."
sleep 30

# =========================================================
# STEP 6 — REGISTER SQL SERVER KEY
# =========================================================

if az sql server key show \
    --server "$SERVER_NAME" \
    --resource-group "$RESOURCE_GROUP" \
    --kid "$TDE_KEY_ID" \
    &>/dev/null
then

    echo "SQL Server key exists"

else

    az sql server key create \
      --server "$SERVER_NAME" \
      --resource-group "$RESOURCE_GROUP" \
      --kid "$TDE_KEY_ID"

fi

# =========================================================
# STEP 7 — CONFIGURE TDE PROTECTOR
# =========================================================

echo "Checking TDE protector configuration..."

CURRENT_TDE_KEY=$(
    az sql server tde-key show \
        --server "$SERVER_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --query uri \
        -o tsv 2>/dev/null || true
)

if [[ -z "$CURRENT_TDE_KEY" ]]
then

    echo "Setting TDE protector..."

    az sql server tde-key set \
        --server "$SERVER_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --server-key-type AzureKeyVault \
        --kid "$TDE_KEY_ID"

elif [[ "$CURRENT_TDE_KEY" == "$TDE_KEY_ID" ]]
then

    echo "TDE protector already configured"

else

    echo "Updating TDE protector..."

    az sql server tde-key set \
        --server "$SERVER_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --server-key-type AzureKeyVault \
        --kid "$TDE_KEY_ID"

fi

# =========================================================
# COMPLETE
# =========================================================

echo ""
echo "Deployment complete"
echo "SQL Server : $SERVER_NAME"
echo "Database   : $DB_NAME"
echo "Public IP  : $MY_IP"