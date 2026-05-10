#!/bin/bash

set -euo pipefail

# =========================================================
# VARIABLES
# ========================================================= 

RESOURCE_GROUP=$(az group list --query "[1].name" -o tsv)  # Change this to your resource group if needed
LOCATION=$(az group show --name "$RESOURCE_GROUP" --query "location" -o tsv)
SERVER_NAME="sqlserver-234809"
DB_NAME="demo-db"
ADMIN_USER="sqladmin"
ADMIN_PASSWORD="R3P1IKA5X_123"  # In production, use a secure method to handle passwords
FIREWALL_RULE_NAME="AllowMyIP"
VM_FIREWALL_RULE_NAME="AllowVMIP"

VM_IP=$(az vm list-ip-addresses \
  --resource-group "$RESOURCE_GROUP" \
  --name "vm-234809" \
  --query "[0].virtualMachine.network.publicIpAddresses[0].ipAddress" \
  -o tsv)

KV_NAME=$(az keyvault list \
  --resource-group "$RESOURCE_GROUP" \
  --query "[?contains(name, '-234809')].name | [0]" \
  -o tsv)

TDE_KEY_ID=$(az keyvault key show \
  --vault-name $KV_NAME \
  --name tde-encrypted-key \
  --query key.kid -o tsv)

# =========================================================
# VALIDATE RESOURCE GROUP EXISTS
# =========================================================

if ! az group exists --name "$RESOURCE_GROUP" | grep -q true; then
    echo "ERROR: Resource group '$RESOURCE_GROUP' does not exist."
    exit 1

fi


# =========================================================
# GET CLIENT PUBLIC IP
# =========================================================

MY_IP=$(curl -s https://api.ipify.org)

if [[ -z "$MY_IP" ]]; then
    echo "ERROR: Failed to retrieve public IP."
    exit 1
fi


# =========================================================
# STEP 1 — CREATE SQL SERVER
# =========================================================
echo "Creating Azure SQL logical server..."

if az sql server show \
    --name "$SERVER_NAME" \
    --resource-group "$RESOURCE_GROUP" &>/dev/null
then
    echo "SQL Server already exists: $SERVER_NAME"
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
# VARIABLES
# =========================================================

SQL_MI=$(az sql server show \
  --name $SERVER_NAME \
  --resource-group $RESOURCE_GROUP \
  --query identity.principalId -o tsv)

POLICY_EXISTS=$(az keyvault show \
  --name "$KV_NAME" \
  --query "properties.accessPolicies[?objectId=='$SQL_MI'].objectId | [0]" \
  -o tsv)


# =========================================================
# STEP 2 — CONFIGURE TDE WITH CUSTOMER-MANAGED KEYS
# =========================================================
if [[ "$POLICY_EXISTS" == "$SQL_MI" ]]; then
    echo "Key Vault policy already exists for SQL MI"
else
    az keyvault set-policy \
      --name $KV_NAME \
      --object-id $SQL_MI \
      --key-permissions get WrapKey UnwrapKey
fi

echo "Waiting for Key Vault policy propagation..."
sleep 60

if az sql server key show \
    --server "$SERVER_NAME" \
    --resource-group "$RESOURCE_GROUP" \
    --kid "$TDE_KEY_ID" &>/dev/null
then
    echo "SQL Server key already exists"
else
    az sql server key create \
      --server "$SERVER_NAME" \
      --resource-group "$RESOURCE_GROUP" \
      --kid "$TDE_KEY_ID"
fi


SERVER_NAME=$(az sql server list \
  --resource-group "$RESOURCE_GROUP" \
  --query "[?contains(name, '-234809')].name | [0]" \
  -o tsv)
echo $SERVER_NAME

CURRENT_TDE_KEY=$(az sql server tde-key show \
    --server "$SERVER_NAME" \
    --resource-group "$RESOURCE_GROUP" \
    --query uri \
    -o tsv 2>/dev/null)

if [[ "$CURRENT_TDE_KEY" == "$TDE_KEY_ID" ]]; then
    echo "TDE key already configured"
else
    az sql server tde-key set \
      --server "$SERVER_NAME" \
      --resource-group "$RESOURCE_GROUP" \
      --server-key-type AzureKeyVault \
      --kid "$TDE_KEY_ID"
fi

# =========================================================
# STEP 2 — ENABLE MANAGED IDENTITY
# =========================================================

# =========================================================
# STEP 3 — CREATE FIREWALL RULE
# =========================================================

echo "Creating firewall rule..."

if az sql server firewall-rule show \
    --resource-group "$RESOURCE_GROUP" \
    --server "$SERVER_NAME" \
    --name "$FIREWALL_RULE_NAME" &>/dev/null
then
    echo "Firewall rule already exists: $FIREWALL_RULE_NAME"
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
    --name "$VM_FIREWALL_RULE_NAME" &>/dev/null
then
    echo "Firewall rule already exists: $VM_FIREWALL_RULE_NAME"
else
    az sql server firewall-rule create \
        --resource-group "$RESOURCE_GROUP" \
        --server "$SERVER_NAME" \
        --name "$VM_FIREWALL_RULE_NAME" \
        --start-ip-address "$VM_IP" \
        --end-ip-address "$VM_IP"
fi

# =========================================================
# STEP 4 — CREATE DATABASE
# =========================================================

echo "Creating database..."

if az sql db show \
    --resource-group "$RESOURCE_GROUP" \
    --server "$SERVER_NAME" \
    --name "$DB_NAME" &>/dev/null
then
    echo "Database already exists: $DB_NAME"
else
    az sql db create \
        --resource-group "$RESOURCE_GROUP" \
        --server "$SERVER_NAME" \
        --name "$DB_NAME" \
        --edition Basic \
        --max-size 2GB
fi

# =========================================================
# COMPLETE
# =========================================================

echo ""

echo "Deployment complete."

echo "SQL Server : $SERVER_NAME"

echo "Database   : $DB_NAME"

echo "Public IP  : $MY_IP"

