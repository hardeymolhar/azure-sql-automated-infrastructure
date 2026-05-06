#!/bin/bash
set -euo pipefail

# 1. Get resource group FIRST
RESOURCE_GROUP=$(az group list --query "[0].name" -o tsv)


# 2. Get server name safely
SERVER_NAME=$(az sql server list \
  --resource-group "$RESOURCE_GROUP" \
  --query "[0].name" \
  -o tsv)

# 3. Get signed-in user details
DISPLAY_NAME=$(az ad signed-in-user show --query userPrincipalName -o tsv)
OBJECT_ID=$(az ad signed-in-user show --query "id" -o tsv)


# 4. Set Entra admin
az sql server ad-admin create \
  --resource-group "$RESOURCE_GROUP" \
  --server "$SERVER_NAME" \
  --display-name "$DISPLAY_NAME" \
  --object-id "$OBJECT_ID"