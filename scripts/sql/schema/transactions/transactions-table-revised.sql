CREATE TABLE dbo.tbl_transactions_secure_AEK
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
    MASKED WITH (FUNCTION = 'partial(1,"****",1)')
    NOT NULL,

    created_by NVARCHAR(100)
    MASKED WITH (FUNCTION = 'partial(1,"****",1)')
    NULL,

    modified_by NVARCHAR(100)
    MASKED WITH (FUNCTION = 'partial(1,"****",1)')
    NULL,

    created_on DATETIME2 NOT NULL,

    modified_on DATETIME2 NULL,

    -- Transaction lifecycle
    transaction_request_date DATETIME2 NULL,

    transaction_response_date DATETIME2 NULL,

    reversed BIT NULL,

    vat_inclusive BIT NULL
);
GO