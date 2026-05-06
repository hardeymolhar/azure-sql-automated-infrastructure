#!/bin/bash

set -euo pipefail

# Variables
RESOURCE_GROUP=$(az group list --query "[0].name" -o tsv)  # Change this to your resource group if needed
LOCATION="eastus"
SERVER_NAME="sqlserver$RANDOM"
ADMIN_USER="sqladminuser"
ADMIN_PASSWORD="r3P1iKa5x_123$"   # change this
DB_NAME="demo-db"

# 2. Create SQL Server
az sql server create \
  --name $SERVER_NAME \
  --resource-group $RESOURCE_GROUP \
  --location $LOCATION \
  --admin-user $ADMIN_USER \
  --admin-password $ADMIN_PASSWORD

# 3. Allow your IP (IMPORTANT)
az sql server firewall-rule create \
  --resource-group $RESOURCE_GROUP \
  --server $SERVER_NAME \
  --name AllowMyIP \
  --start-ip-address 0.0.0.0 \
  --end-ip-address 0.0.0.0

# 4. Create Database
az sql db create \
  --resource-group $RESOURCE_GROUP \
  --server $SERVER_NAME \
  --name $DB_NAME \
  --service-objective Basic \
  --max-size 2GB