CREATE TABLE dbo.pc_cards_secure
(
    -- Operational identifiers
    issuer_nr INT NOT NULL,

    card_program VARCHAR(20) NOT NULL,

    default_account_type CHAR(2) NOT NULL,

    card_status INT NOT NULL,

    issuer_reference VARCHAR(20) NULL,

    branch_code VARCHAR(10) NULL,

    -- PAN storage (encrypted)
    pan_encrypted VARCHAR(72) COLLATE Latin1_General_BIN2
    ENCRYPTED WITH
    (
        COLUMN_ENCRYPTION_KEY = CEK_Auto1,
        ENCRYPTION_TYPE = DETERMINISTIC,
        ALGORITHM = 'AEAD_AES_256_CBC_HMAC_SHA_256'
    )
    NULL,

    -- Card lifecycle
    expiry_date CHAR(4) NULL,

    date_issued DATETIME2 NULL,

    date_activated DATETIME2 NULL,

    expiry_date_time DATETIME2 NULL,

    -- Customer linkage (PII)
    customer_id VARCHAR(25)
    MASKED WITH (FUNCTION = 'partial(1,"******",2)')
    NULL,

    -- Audit accountability
    last_updated_user VARCHAR(20)
    MASKED WITH (FUNCTION = 'partial(1,"****",1)')
    NOT NULL,

    last_updated_date DATETIME2 NOT NULL,

    CONSTRAINT PK_pc_cards_secure
    PRIMARY KEY CLUSTERED (issuer_nr, card_program)
);
GO
