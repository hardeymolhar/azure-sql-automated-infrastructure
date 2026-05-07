#!/bin/bash
set -euo pipefail

# 1. Get resource group FIRST
RESOURCE_GROUP=$(az group list --query "[1].name" -o tsv)


# 2. Get server name safely
SERVER_NAME=$(az sql server list \
  --resource-group "$RESOURCE_GROUP" \
  --query "[0].name" \
  -o tsv)

# =========================================================
# VALIDATE RESOURCE GROUP
# =========================================================

if ! az group exists --name "$RESOURCE_GROUP" | grep -q true; then

    echo "ERROR: Resource group '$RESOURCE_GROUP' does not exist."

    exit 1

fi

# =========================================================
# VALIDATE SQL SERVER
# =========================================================

SERVER_EXISTS=$(az sql server show \
    --resource-group "$RESOURCE_GROUP" \
    --name "$SERVER_NAME" \
    --query "name" \
    -o tsv 2>/dev/null || true)

if [[ -z "$SERVER_EXISTS" ]]; then

    echo "ERROR: SQL Server '$SERVER_NAME' does not exist."

    exit 1

fi

# =========================================================
# GET SIGNED-IN USER DETAILS
# =========================================================

DISPLAY_NAME=$(az ad signed-in-user show \
    --query userPrincipalName \
    -o tsv)

OBJECT_ID=$(az ad signed-in-user show \
    --query id \
    -o tsv)

# =========================================================
# SET MICROSOFT ENTRA ADMIN
# =========================================================

echo "Configuring Microsoft Entra admin..."

az sql server ad-admin create \
    --resource-group "$RESOURCE_GROUP" \
    --server "$SERVER_NAME" \
    --display-name "$DISPLAY_NAME" \
    --object-id "$OBJECT_ID"

echo ""

echo "Microsoft Entra admin configured successfully."

echo "Server      : $SERVER_NAME"
echo "Admin User  : $DISPLAY_NAME"