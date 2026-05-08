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

ACCESS_TOKEN=$(az account get-access-token \
  --resource https://database.windows.net/ \
  --query accessToken \
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
  --access-token "$ACCESS_TOKEN" \
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



# ==========================================
# CREATE TABLE + CLASSIFICATIONS
# ==========================================

sqlcmd \
  -S "${SQL_SERVER_NAME}.database.windows.net" \
  -d "$DATABASE_NAME" \
  -N \
  -C \
  --access-token "$ACCESS_TOKEN" \
  -Q "

-- ==========================================
-- CREATE TABLE IF NOT EXISTS
-- ==========================================

IF OBJECT_ID('dbo.tbl_transactions_secure', 'U') IS NULL
BEGIN

CREATE TABLE dbo.tbl_transactions_secure
(
    id BIGINT IDENTITY(63264900,1)
    NOT NULL PRIMARY KEY,

    transaction_sub_type NVARCHAR(31) NOT NULL,

    transaction_type NVARCHAR(50) NOT NULL,

    amount DECIMAL(19,2) NULL,

    charged_fee DECIMAL(19,2) NULL,

    currency_code CHAR(3) NOT NULL,

    source_account_number VARCHAR(20)
    MASKED WITH (FUNCTION = 'partial(0,\"XXXXXX\",4)')
    NULL,

    destination_account_number VARCHAR(20)
    MASKED WITH (FUNCTION = 'partial(0,\"XXXXXX\",4)')
    NULL,

    destination_account_name NVARCHAR(150)
    MASKED WITH (FUNCTION = 'partial(1,\"******\",1)')
    NULL,

    destination_bank_code VARCHAR(10) NULL,

    destination_bank_name NVARCHAR(100) NULL,

    transaction_reference VARCHAR(100) NOT NULL,

    transaction_external_reference VARCHAR(100) NULL,

    transaction_posting_reference VARCHAR(100) NULL,

    request_transaction_id VARCHAR(100) NULL,

    transaction_final_status VARCHAR(50) NULL,

    transaction_request_status VARCHAR(50) NULL,

    session_key VARCHAR(255)
    MASKED WITH (FUNCTION = 'default()')
    NULL,

    recharge_pin VARCHAR(50)
    MASKED WITH (FUNCTION = 'default()')
    NULL,

    electricity_token VARCHAR(100)
    MASKED WITH (FUNCTION = 'default()')
    NULL,

    user_name NVARCHAR(50)
    MASKED WITH (FUNCTION = 'partial(1,\"****\",1)')
    NOT NULL,

    created_by NVARCHAR(100)
    MASKED WITH (FUNCTION = 'partial(1,\"****\",1)')
    NULL,

    modified_by NVARCHAR(100)
    MASKED WITH (FUNCTION = 'partial(1,\"****\",1)')
    NULL,

    created_on DATETIME2 NOT NULL,

    modified_on DATETIME2 NULL,

    transaction_request_date DATETIME2 NULL,

    transaction_response_date DATETIME2 NULL,

    reversed BIT NULL,

    vat_inclusive BIT NULL
);

END;

-- ==========================================
-- SENSITIVITY CLASSIFICATIONS
-- ==========================================

IF NOT EXISTS (
    SELECT 1
    FROM sys.sensitivity_classifications
    WHERE major_id = OBJECT_ID('dbo.tbl_transactions_secure')
    AND minor_id = COLUMNPROPERTY(
        OBJECT_ID('dbo.tbl_transactions_secure'),
        'amount',
        'ColumnId'
    )
)
BEGIN
ADD SENSITIVITY CLASSIFICATION TO dbo.tbl_transactions_secure.amount
WITH (
    LABEL = 'Confidential',
    INFORMATION_TYPE = 'Financial'
);
END;

IF NOT EXISTS (
    SELECT 1
    FROM sys.sensitivity_classifications
    WHERE major_id = OBJECT_ID('dbo.tbl_transactions_secure')
    AND minor_id = COLUMNPROPERTY(
        OBJECT_ID('dbo.tbl_transactions_secure'),
        'source_account_number',
        'ColumnId'
    )
)
BEGIN
ADD SENSITIVITY CLASSIFICATION TO dbo.tbl_transactions_secure.source_account_number
WITH (
    LABEL = 'Highly Confidential',
    INFORMATION_TYPE = 'Financial'
);
END;

IF NOT EXISTS (
    SELECT 1
    FROM sys.sensitivity_classifications
    WHERE major_id = OBJECT_ID('dbo.tbl_transactions_secure')
    AND minor_id = COLUMNPROPERTY(
        OBJECT_ID('dbo.tbl_transactions_secure'),
        'destination_account_number',
        'ColumnId'
    )
)
BEGIN
ADD SENSITIVITY CLASSIFICATION TO dbo.tbl_transactions_secure.destination_account_number
WITH (
    LABEL = 'Highly Confidential',
    INFORMATION_TYPE = 'Financial'
);
END;

IF NOT EXISTS (
    SELECT 1
    FROM sys.sensitivity_classifications
    WHERE major_id = OBJECT_ID('dbo.tbl_transactions_secure')
    AND minor_id = COLUMNPROPERTY(
        OBJECT_ID('dbo.tbl_transactions_secure'),
        'destination_account_name',
        'ColumnId'
    )
)
BEGIN
ADD SENSITIVITY CLASSIFICATION TO dbo.tbl_transactions_secure.destination_account_name
WITH (
    LABEL = 'Confidential',
    INFORMATION_TYPE = 'Personal'
);
END;

IF NOT EXISTS (
    SELECT 1
    FROM sys.sensitivity_classifications
    WHERE major_id = OBJECT_ID('dbo.tbl_transactions_secure')
    AND minor_id = COLUMNPROPERTY(
        OBJECT_ID('dbo.tbl_transactions_secure'),
        'session_key',
        'ColumnId'
    )
)
BEGIN
ADD SENSITIVITY CLASSIFICATION TO dbo.tbl_transactions_secure.session_key
WITH (
    LABEL = 'Highly Confidential',
    INFORMATION_TYPE = 'Credential'
);
END;

IF NOT EXISTS (
    SELECT 1
    FROM sys.sensitivity_classifications
    WHERE major_id = OBJECT_ID('dbo.tbl_transactions_secure')
    AND minor_id = COLUMNPROPERTY(
        OBJECT_ID('dbo.tbl_transactions_secure'),
        'recharge_pin',
        'ColumnId'
    )
)
BEGIN
ADD SENSITIVITY CLASSIFICATION TO dbo.tbl_transactions_secure.recharge_pin
WITH (
    LABEL = 'Highly Confidential',
    INFORMATION_TYPE = 'Credential'
);
END;

IF NOT EXISTS (
    SELECT 1
    FROM sys.sensitivity_classifications
    WHERE major_id = OBJECT_ID('dbo.tbl_transactions_secure')
    AND minor_id = COLUMNPROPERTY(
        OBJECT_ID('dbo.tbl_transactions_secure'),
        'electricity_token',
        'ColumnId'
    )
)
BEGIN
ADD SENSITIVITY CLASSIFICATION TO dbo.tbl_transactions_secure.electricity_token
WITH (
    LABEL = 'Confidential',
    INFORMATION_TYPE = 'Credential'
);
END;

IF NOT EXISTS (
    SELECT 1
    FROM sys.sensitivity_classifications
    WHERE major_id = OBJECT_ID('dbo.tbl_transactions_secure')
    AND minor_id = COLUMNPROPERTY(
        OBJECT_ID('dbo.tbl_transactions_secure'),
        'user_name',
        'ColumnId'
    )
)
BEGIN
ADD SENSITIVITY CLASSIFICATION TO dbo.tbl_transactions_secure.user_name
WITH (
    LABEL = 'Confidential',
    INFORMATION_TYPE = 'Personal'
);
END;

IF NOT EXISTS (
    SELECT 1
    FROM sys.sensitivity_classifications
    WHERE major_id = OBJECT_ID('dbo.tbl_transactions_secure')
    AND minor_id = COLUMNPROPERTY(
        OBJECT_ID('dbo.tbl_transactions_secure'),
        'created_by',
        'ColumnId'
    )
)
BEGIN
ADD SENSITIVITY CLASSIFICATION TO dbo.tbl_transactions_secure.created_by
WITH (
    LABEL = 'Confidential',
    INFORMATION_TYPE = 'Organizational'
);
END;

IF NOT EXISTS (
    SELECT 1
    FROM sys.sensitivity_classifications
    WHERE major_id = OBJECT_ID('dbo.tbl_transactions_secure')
    AND minor_id = COLUMNPROPERTY(
        OBJECT_ID('dbo.tbl_transactions_secure'),
        'modified_by',
        'ColumnId'
    )
)
BEGIN
ADD SENSITIVITY CLASSIFICATION TO dbo.tbl_transactions_secure.modified_by
WITH (
    LABEL = 'Confidential',
    INFORMATION_TYPE = 'Organizational'
);
END;
"

echo "=========================================="
echo "Secure transaction table deployed."
echo "=========================================="