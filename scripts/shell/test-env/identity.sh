#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/env.conf"


SQL_SERVER_NAME="$(printf '%s' "$SQL_SERVER_NAME" | tr -d '[:space:]')"
SQL_SERVER_FQDN="${SQL_SERVER_NAME}.database.windows.net"

if [[ -z "$SQL_SERVER_NAME" ]]; then
  echo -e "${RED}ERROR: No Azure SQL server found. Set SERVER_NAME before running this script.${NC}"
  exit 1
fi

echo -e "${BLUE}SQL Server: $SQL_SERVER_NAME${NC}"
echo -e "${BLUE}SQL FQDN:   $SQL_SERVER_FQDN${NC}"

DISPLAY_NAME=$(az ad signed-in-user show \
    --query userPrincipalName \
    -o tsv)

#========================
# FETCH EXISTING VM NAME
# =======================
echo -e "${BLUE}VM Name: $VM_NAME${NC}"


if [[ -x "/opt/homebrew/opt/mssql-tools18/bin/sqlcmd" ]]; then
  SQLCMD_BIN="/opt/homebrew/opt/mssql-tools18/bin/sqlcmd"
else
  SQLCMD_BIN="sqlcmd"
fi


ACCESS_TOKEN_FILE="$(mktemp)"
trap 'rm -f "$ACCESS_TOKEN_FILE"' EXIT

az account get-access-token \
  --resource https://database.windows.net/ \
  --query accessToken \
  -o tsv \
  | tr -d '\n' \
  | iconv -f UTF-8 -t UTF-16LE > "$ACCESS_TOKEN_FILE"


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

# Entra Auth with username + password ( less secure )


# Entra Auth - Interactive (Azure CLI must be logged in)
# sqlcmd \
#   -S "${SQL_SERVER_NAME}.database.windows.net" \
#   -d "$DATABASE_NAME" \
#   -G \
#   -P "$ACCESS_TOKEN_FILE" \
#   -N \
#   -C
  

# ==========================================
# EXECUTE SQL COMMANDS
# ==========================================
"$SQLCMD_BIN" \
  -S "$SQL_SERVER_FQDN" \
  -d "$DATABASE_NAME" \
  -N \
  -C \
  -G \
 -P "$ACCESS_TOKEN_FILE" \
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

IF NOT EXISTS (
    SELECT 1
    FROM sys.database_principals
    WHERE name = 'test_user'
)
BEGIN
    CREATE USER [test_user]
    WITH PASSWORD = 'r3P1iKa5x_123';
END;

ALTER ROLE db_datareader
ADD MEMBER [$VM_NAME];

ALTER ROLE db_datawriter
ADD MEMBER [$VM_NAME];

ALTER ROLE db_datareader
ADD MEMBER [test_user];


GRANT VIEW ANY COLUMN MASTER KEY DEFINITION TO [$VM_NAME];

GRANT VIEW ANY COLUMN ENCRYPTION KEY DEFINITION TO [$VM_NAME];

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

echo -e "${GREEN}=========================================="
echo -e "${GREEN}Managed Identity user configured.${NC}"
echo -e "${GREEN}Test user with password configured.${NC}"
echo -e "${GREEN}Query Store configured.${NC}"
echo -e "${GREEN}==========================================${NC}"



# ==========================================
# CREATE TABLE + CLASSIFICATIONS
# ==========================================

"$SQLCMD_BIN" \
  -S "$SQL_SERVER_FQDN" \
  -d "$DATABASE_NAME" \
  -N \
  -C \
  -G \
  -P "$ACCESS_TOKEN_FILE" \
  -Q "

-- ==========================================
-- CREATE TABLE IF NOT EXISTS
-- ==========================================

IF OBJECT_ID('dbo.tbl_transactions_secure', 'U') IS NULL
BEGIN

CREATE TABLE dbo.tbl_transactions_secure
(
    -- Primary identifier
    id BIGINT IDENTITY(63264900,1)
    NOT NULL PRIMARY KEY,

    -- Transaction classification
    transaction_sub_type NVARCHAR(31) NOT NULL,

    transaction_type NVARCHAR(50) NOT NULL,

    -- Financial values
    amount DECIMAL(19,2) NULL,

    charged_fee DECIMAL(19,2) NULL,

    currency_code CHAR(3) NOT NULL,

    -- Account identifiers (searchable)
    source_account_number NVARCHAR(20)
    COLLATE Latin1_General_BIN2
    ENCRYPTED WITH
    (
        COLUMN_ENCRYPTION_KEY = AE_CEK,
        ENCRYPTION_TYPE = DETERMINISTIC,
        ALGORITHM = 'AEAD_AES_256_CBC_HMAC_SHA_256'
    )
    NULL,

    destination_account_number NVARCHAR(20)
    COLLATE Latin1_General_BIN2
    ENCRYPTED WITH
    (
        COLUMN_ENCRYPTION_KEY = AE_CEK,
        ENCRYPTION_TYPE = DETERMINISTIC,
        ALGORITHM = 'AEAD_AES_256_CBC_HMAC_SHA_256'
    )
    NULL,

    -- Sensitive PII
    destination_account_name NVARCHAR(150)
    ENCRYPTED WITH
    (
        COLUMN_ENCRYPTION_KEY = AE_CEK,
        ENCRYPTION_TYPE = RANDOMIZED,
        ALGORITHM = 'AEAD_AES_256_CBC_HMAC_SHA_256'
    )
    NULL,

    destination_bank_code VARCHAR(10) NULL,

    destination_bank_name NVARCHAR(100) NULL,

    -- Transaction traceability
    transaction_reference VARCHAR(100) NOT NULL,

    transaction_external_reference VARCHAR(100) NULL,

    transaction_posting_reference VARCHAR(100) NULL,

    request_transaction_id VARCHAR(100) NULL,

    -- Status tracking
    transaction_final_status VARCHAR(50) NULL,

    transaction_request_status VARCHAR(50) NULL,

    -- Sensitive secrets/tokens
    session_key NVARCHAR(255)
    ENCRYPTED WITH
    (
        COLUMN_ENCRYPTION_KEY = AE_CEK,
        ENCRYPTION_TYPE = RANDOMIZED,
        ALGORITHM = 'AEAD_AES_256_CBC_HMAC_SHA_256'
    )
    NULL,

    recharge_pin NVARCHAR(50)
    ENCRYPTED WITH
    (
        COLUMN_ENCRYPTION_KEY = AE_CEK,
        ENCRYPTION_TYPE = RANDOMIZED,
        ALGORITHM = 'AEAD_AES_256_CBC_HMAC_SHA_256'
    )
    NULL,

    electricity_token NVARCHAR(100)
    ENCRYPTED WITH
    (
        COLUMN_ENCRYPTION_KEY = AE_CEK,
        ENCRYPTION_TYPE = RANDOMIZED,
        ALGORITHM = 'AEAD_AES_256_CBC_HMAC_SHA_256'
    )
    NULL,

    -- Audit accountability
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

    -- Transaction lifecycle
    transaction_request_date DATETIME2 NULL,

    transaction_response_date DATETIME2 NULL,

    reversed BIT NULL,

    vat_inclusive BIT NULL
);

CREATE NONCLUSTERED INDEX IX_Count_Only
ON dbo.tbl_transactions_secure (id);

CREATE CLUSTERED INDEX IX_transactions_created_on
ON dbo.tbl_transactions_secure(created_on);

CREATE NONCLUSTERED INDEX IX_transactions_source_account
ON dbo.tbl_transactions_secure(source_account_number);

CREATE NONCLUSTERED INDEX IX_transactions_status
ON dbo.tbl_transactions_secure(transaction_final_status);

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

echo -e "${GREEN}==========================================${NC}"
echo -e "${GREEN}Secure transaction table deployed.${NC}"
echo -e "${GREEN}==========================================${NC}"



