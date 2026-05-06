#!/bin/bash

set -euo pipefail

# Variables
RESOURCE_GROUP=$(az group list --query "[0].name" -o tsv)  # Change this to your resource group if needed
LOCATION="eastus"
SERVER_NAME="sqlserver-$RANDOM"
#SERVER_NAME="sqlserver-21459"  --- IGNORE ---
ADMIN_USER="sqladminuser"
ADMIN_PASSWORD="r3P1iKa5x_123$"   # change this
DB_NAME="demo-db"
MY_IP=$(curl -s https://api.ipify.org)




# 2. Create SQL Server
az sql server create \
  --name $SERVER_NAME \
  --resource-group $RESOURCE_GROUP \
  --location $LOCATION \
  --admin-user $ADMIN_USER \
  --admin-password $ADMIN_PASSWORD

# 3. Allow your Client IP (IMPORTANT)
az sql server firewall-rule create \
  --resource-group $RESOURCE_GROUP \
  --server $SERVER_NAME \
  --name AllowMyIP \
  --start-ip-address "$MY_IP" \
  --end-ip-address "$MY_IP"

# 4. Create Database
az sql db create \
  --resource-group $RESOURCE_GROUP \
  --server $SERVER_NAME \
  --name $DB_NAME \
  --service-objective Basic \
  --max-size 2GB