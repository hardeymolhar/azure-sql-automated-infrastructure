#!/bin/bash
set -euo pipefail

# 1. Get resource group FIRST
RESOURCE_GROUP=$(az group list --query "[1].name" -o tsv)


SERVER_NAME=$(az sql server list \
  --resource-group "$RESOURCE_GROUP" \
  --query "[?contains(name, '-2348112')].name | [0]" \
  -o tsv)

# =========================================================
# VALIDATE RESOURCE GROUP
# =========================================================

if ! az group exists --name "$RESOURCE_GROUP" | grep -q true; then

    echo "ERROR: Resource group '$RESOURCE_GROUP' does not exist."

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

if az sql server ad-admin list \
    --resource-group "$RESOURCE_GROUP" \
    --server "$SERVER_NAME" \
    --query "[?objectId=='$OBJECT_ID'] | [0]" \
    -o tsv | grep -q "$OBJECT_ID"
then
    echo "Microsoft Entra admin already configured."
else
    az sql server ad-admin create \
        --resource-group "$RESOURCE_GROUP" \
        --server "$SERVER_NAME" \
        --display-name "$DISPLAY_NAME" \
        --object-id "$OBJECT_ID"
fi

echo ""

echo "Microsoft Entra admin configured successfully."

echo "Server      : $SERVER_NAME"
echo "Admin User  : $DISPLAY_NAME"