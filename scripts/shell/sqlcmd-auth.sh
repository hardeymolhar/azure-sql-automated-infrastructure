#!/bin/bash
set -euo pipefail

RESOURCE_GROUP=$(az group list --query "[1].name" -o tsv)
SQL_SERVER_NAME=$(az sql server list \
  --resource-group "$RESOURCE_GROUP" \
  --query "[0].name" \
  -o tsv)
#==========================================
# FETCH EXISTING VM NAME
# ==========================================

VM_NAME=$(az vm list \
  --resource-group "$RESOURCE_GROUP" \
  --query "[0].name" \
  -o tsv)
echo "VM Name: $VM_NAME"


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
#!/bin/bash

set -euo pipefail

# ==========================================
# VARIABLES
# ==========================================

RESOURCE_GROUP="your-resource-group"

SQL_SERVER_NAME="your-sql-server"

DATABASE_NAME="demo-db"

ADMIN_USER="your-email@tenant.com"

# ==========================================
# FETCH EXISTING VM NAME
# ==========================================

VM_NAME=$(az vm list \
  --resource-group "$RESOURCE_GROUP" \
  --query "[0].name" \
  -o tsv)

echo "VM Name: $VM_NAME"

# ==========================================
# EXECUTE SQL COMMANDS
# ==========================================

sqlcmd \
  -S "${SQL_SERVER_NAME}.database.windows.net" \
  -d "$DATABASE_NAME" \
  -N \
  -C \
  -G \
  -U "$ADMIN_USER" \
  -Q "
IF NOT EXISTS (
    SELECT 1
    FROM sys.database_principals
    WHERE name = '$VM_NAME'
)
BEGIN
    CREATE USER [$VM_NAME]
    FROM EXTERNAL PROVIDER;
END;

ALTER ROLE db_datareader
ADD MEMBER [$VM_NAME];

ALTER ROLE db_datawriter
ADD MEMBER [$VM_NAME];

ALTER DATABASE [$DATABASE_NAME]
SET QUERY_STORE (
    OPERATION_MODE = READ_WRITE,
    CLEANUP_POLICY = (STALE_QUERY_THRESHOLD_DAYS = 30),
    DATA_FLUSH_INTERVAL_SECONDS = 900,
    INTERVAL_LENGTH_MINUTES = 60,
    MAX_STORAGE_SIZE_MB = 2048,
    QUERY_CAPTURE_MODE = AUTO
);
"

echo "=========================================="
echo "Managed Identity user configured."
echo "Query Store configured."
echo "=========================================="