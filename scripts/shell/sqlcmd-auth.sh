#!/bin/bash
set -euo pipefail

RESOURCE_GROUP=$(az group list --query "[1].name" -o tsv)
SQL_SERVER_NAME=$(az sql server list \
  --resource-group "$RESOURCE_GROUP" \
  --query "[0].name" \
  -o tsv)

DATABASE_NAME="demo-db"

ADMIN_USER=$(az ad signed-in-user show \
    --query userPrincipalName \
    -o tsv)
# SQL Login - Prompt for password.
# sqlcmd \
#   -S "${SQL_SERVER_NAME}.database.windows.net" \
#   -d "$DATABASE_NAME" \
#   -U "$ADMIN_USER" \
#   -N \
#   -C


# # SQL Login - Explicit Password 
# sqlcmd \
#   -S "${SQL_SERVER_NAME}.database.windows.net" \
#   -d "$DATABASE_NAME" \
#   -U "$ADMIN_USER" \
#   -P "$ADMIN_PASSWORD" \
#   -N \
#   -C

# # Entra Auth with username + password ( less secure )
# sqlcmd \
#   -S "${SQL_SERVER_NAME}.database.windows.net" \
#   -d "$DATABASE_NAME" \
#   -G \
#   -U "your-email@tenant.com" \
#   -N \
#   -C

  
# Entra Auth - Interactive (Azure CLI must be logged in)
sqlcmd \
  -S "${SQL_SERVER_NAME}.database.windows.net" \
  -d "$DATABASE_NAME" \
  -N \
  -G \
  -U "$ADMIN_USER" 


# ALTER DATABASE [demo-db]
# SET QUERY_STORE (
#     OPERATION_MODE = READ_WRITE,
#     CLEANUP_POLICY = (STALE_QUERY_THRESHOLD_DAYS = 30),
#     DATA_FLUSH_INTERVAL_SECONDS = 900,
#     INTERVAL_LENGTH_MINUTES = 60,
#     MAX_STORAGE_SIZE_MB = 2048,
#     QUERY_CAPTURE_MODE = AUTO
# );

# GO