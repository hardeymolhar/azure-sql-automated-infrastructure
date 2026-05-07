CREATE TABLE dbo.tbl_transactions_secure
(
    -- =====================================================
    -- PRIMARY IDENTIFIER
    -- =====================================================

    id BIGINT IDENTITY(63264900,1)
    NOT NULL PRIMARY KEY,

    -- =====================================================
    -- TRANSACTION CLASSIFICATION
    -- =====================================================

    transaction_sub_type NVARCHAR(31) NOT NULL,

    transaction_type NVARCHAR(50) NOT NULL,

    -- =====================================================
    -- FINANCIAL VALUES
    -- =====================================================

    amount DECIMAL(19,2) NULL,

    charged_fee DECIMAL(19,2) NULL,

    currency_code CHAR(3) NOT NULL,

    -- =====================================================
    -- ACCOUNT IDENTIFIERS
    -- =====================================================

    source_account_number NVARCHAR(20) COLLATE Latin1_General_BIN2
    ENCRYPTED WITH
    (
        COLUMN_ENCRYPTION_KEY = AE_CEK,
        ENCRYPTION_TYPE = DETERMINISTIC,
        ALGORITHM = 'AEAD_AES_256_CBC_HMAC_SHA_256'
    )
    NULL,

    destination_account_number NVARCHAR(20) COLLATE Latin1_General_BIN2
    ENCRYPTED WITH
    (
        COLUMN_ENCRYPTION_KEY = AE_CEK,
        ENCRYPTION_TYPE = DETERMINISTIC,
        ALGORITHM = 'AEAD_AES_256_CBC_HMAC_SHA_256'
    )
    NULL,

    destination_account_name NVARCHAR(150) COLLATE Latin1_General_BIN2
    ENCRYPTED WITH
    (
        COLUMN_ENCRYPTION_KEY = AE_CEK,
        ENCRYPTION_TYPE = RANDOMIZED,
        ALGORITHM = 'AEAD_AES_256_CBC_HMAC_SHA_256'
    )
    NULL,

    destination_bank_code VARCHAR(10) NULL,

    destination_bank_name NVARCHAR(100) NULL,

    -- =====================================================
    -- TRANSACTION TRACEABILITY
    -- =====================================================

    transaction_reference NVARCHAR(100) NOT NULL,

    transaction_external_reference NVARCHAR(100) NULL,

    transaction_posting_reference NVARCHAR(100) NULL,

    request_transaction_id NVARCHAR(100) NULL,

    -- =====================================================
    -- STATUS TRACKING
    -- =====================================================

    transaction_final_status VARCHAR(50) NULL,

    transaction_request_status VARCHAR(50) NULL,

    -- =====================================================
    -- SENSITIVE OPERATIONAL SECRETS
    -- =====================================================

    session_key NVARCHAR(255) COLLATE Latin1_General_BIN2
    ENCRYPTED WITH
    (
        COLUMN_ENCRYPTION_KEY = AE_CEK,
        ENCRYPTION_TYPE = RANDOMIZED,
        ALGORITHM = 'AEAD_AES_256_CBC_HMAC_SHA_256'
    )
    NULL,

    recharge_pin NVARCHAR(50) COLLATE Latin1_General_BIN2
    ENCRYPTED WITH
    (
        COLUMN_ENCRYPTION_KEY = AE_CEK,
        ENCRYPTION_TYPE = RANDOMIZED,
        ALGORITHM = 'AEAD_AES_256_CBC_HMAC_SHA_256'
    )
    NULL,

    electricity_token NVARCHAR(100) COLLATE Latin1_General_BIN2
    ENCRYPTED WITH
    (
        COLUMN_ENCRYPTION_KEY = AE_CEK,
        ENCRYPTION_TYPE = RANDOMIZED,
        ALGORITHM = 'AEAD_AES_256_CBC_HMAC_SHA_256'
    )
    NULL,

    -- =====================================================
    -- AUDIT ACCOUNTABILITY
    -- =====================================================

    user_name NVARCHAR(50) COLLATE Latin1_General_BIN2
    ENCRYPTED WITH
    (
        COLUMN_ENCRYPTION_KEY = AE_CEK,
        ENCRYPTION_TYPE = DETERMINISTIC,
        ALGORITHM = 'AEAD_AES_256_CBC_HMAC_SHA_256'
    )
    NOT NULL,

    created_by NVARCHAR(100)
    MASKED WITH (FUNCTION = 'partial(1,"****",1)')
    NULL,

    modified_by NVARCHAR(100)
    MASKED WITH (FUNCTION = 'partial(1,"****",1)')
    NULL,

    created_on DATETIME2 NOT NULL,

    modified_on DATETIME2 NULL,

    -- =====================================================
    -- TRANSACTION LIFECYCLE
    -- =====================================================

    transaction_request_date DATETIME2 NULL,

    transaction_response_date DATETIME2 NULL,

    reversed BIT NULL,

    vat_inclusive BIT NULL
);
GO


-- =========================================================
-- SENSITIVITY CLASSIFICATIONS
-- =========================================================

ADD SENSITIVITY CLASSIFICATION TO dbo.tbl_transactions_secure.amount
WITH
(
    LABEL = 'Confidential',
    INFORMATION_TYPE = 'Financial'
);
GO

ADD SENSITIVITY CLASSIFICATION TO dbo.tbl_transactions_secure.source_account_number
WITH
(
    LABEL = 'Highly Confidential',
    INFORMATION_TYPE = 'Financial'
);
GO

ADD SENSITIVITY CLASSIFICATION TO dbo.tbl_transactions_secure.destination_account_number
WITH
(
    LABEL = 'Highly Confidential',
    INFORMATION_TYPE = 'Financial'
);
GO

ADD SENSITIVITY CLASSIFICATION TO dbo.tbl_transactions_secure.destination_account_name
WITH
(
    LABEL = 'Confidential',
    INFORMATION_TYPE = 'Personal'
);
GO

ADD SENSITIVITY CLASSIFICATION TO dbo.tbl_transactions_secure.session_key
WITH
(
    LABEL = 'Highly Confidential',
    INFORMATION_TYPE = 'Credential'
);
GO

ADD SENSITIVITY CLASSIFICATION TO dbo.tbl_transactions_secure.recharge_pin
WITH
(
    LABEL = 'Highly Confidential',
    INFORMATION_TYPE = 'Credential'
);
GO

ADD SENSITIVITY CLASSIFICATION TO dbo.tbl_transactions_secure.electricity_token
WITH
(
    LABEL = 'Highly Confidential',
    INFORMATION_TYPE = 'Credential'
);
GO

ADD SENSITIVITY CLASSIFICATION TO dbo.tbl_transactions_secure.user_name
WITH
(
    LABEL = 'Confidential',
    INFORMATION_TYPE = 'Personal'
);
GO

ADD SENSITIVITY CLASSIFICATION TO dbo.tbl_transactions_secure.created_by
WITH
(
    LABEL = 'Confidential',
    INFORMATION_TYPE = 'Organizational'
);
GO

ADD SENSITIVITY CLASSIFICATION TO dbo.tbl_transactions_secure.modified_by
WITH
(
    LABEL = 'Confidential',
    INFORMATION_TYPE = 'Organizational'
);
GO
