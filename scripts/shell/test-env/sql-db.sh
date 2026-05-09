#!/bin/bash

set -euo pipefail

# =========================================================
# VARIABLES
# =========================================================

RESOURCE_GROUP=$(az group list --query "[1].name" -o tsv)  # Change this to your resource group if needed
LOCATION=$(az group show --name "$RESOURCE_GROUP" --query "location" -o tsv)
SERVER_NAME="sqlserver-$RANDOM"
#SERVER_NAME="sqlserver-8622"  
DB_NAME="demo-db"
ADMIN_USER="sqladmin"
FIREWALL_RULE_NAME="AllowMyIP"

KV_NAME=$(az keyvault list \
  --resource-group "$RESOURCE_GROUP" \
  --query "[0].name" \
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
# PROMPT FOR PASSWORD
# =========================================================

read -s -p "Enter SQL admin password: " ADMIN_PASSWORD

printf "\n"

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

az sql server create \
    --name "$SERVER_NAME" \
    --resource-group "$RESOURCE_GROUP" \
    --location "$LOCATION" \
    --admin-user "$ADMIN_USER" \
    --admin-password "$ADMIN_PASSWORD"

az sql server key create \
  --server "$SERVER_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --kid "$TDE_KEY_ID"

SQL_SERVER_NAME="$(
  az sql server list \
    --resource-group "$RESOURCE_GROUP" \
    --query "[0].name" \
    -o tsv)"    

echo $SQL_SERVER_NAME


az sql server tde-key set \
  --server "$SQL_SERVER_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --server-key-type AzureKeyVault \
  --kid "$TDE_KEY_ID"


# =========================================================
# STEP 2 — ENABLE MANAGED IDENTITY
# =========================================================

echo "Enabling managed identity..."

  az sql server update \
    --assign_identity \
    --name $SERVER_NAME \
    --resource-group $RESOURCE_GROUP

SQL_MI=$(az sql server show \
  --name $SQL_SERVER_NAME \
  --resource-group $RESOURCE_GROUP \
  --query identity.principalId -o tsv)

# =========================================================
# STEP 3 — CREATE FIREWALL RULE
# =========================================================

echo "Creating firewall rule..."

az sql server firewall-rule create \
    --resource-group "$RESOURCE_GROUP" \
    --server "$SERVER_NAME" \
    --name "$FIREWALL_RULE_NAME" \
    --start-ip-address "$MY_IP" \
    --end-ip-address "$MY_IP"

# =========================================================
# STEP 4 — CREATE DATABASE
# =========================================================

echo "Creating database..."

az sql db create \
    --resource-group "$RESOURCE_GROUP" \
    --server "$SERVER_NAME" \
    --name "$DB_NAME" \
    --edition Basic \
    --max-size 2GB

# =========================================================
# COMPLETE
# =========================================================

echo ""

echo "Deployment complete."

echo "SQL Server : $SERVER_NAME"

echo "Database   : $DB_NAME"

echo "Public IP  : $MY_IP"


az keyvault set-policy \
  --name $KV_NAME \
  --object-id $SQL_MI \
  --key-permissions get wrapKey unwrapKey


