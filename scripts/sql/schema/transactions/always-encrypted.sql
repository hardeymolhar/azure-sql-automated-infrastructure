SELECT
    c.name AS column_name,
    c.encryption_type_desc,
    cek.name AS column_encryption_key,
    cmk.name AS column_master_key,
    cmk.key_store_provider_name,
    cmk.key_path
FROM sys.columns c

INNER JOIN sys.column_encryption_keys cek
ON c.column_encryption_key_id = cek.column_encryption_key_id

INNER JOIN sys.column_encryption_key_values cekv
ON cek.column_encryption_key_id = cekv.column_encryption_key_id

INNER JOIN sys.column_master_keys cmk
ON cekv.column_master_key_id = cmk.column_master_key_id

WHERE c.object_id = OBJECT_ID('dbo.tbl_transactions_secure')
AND c.encryption_type IS NOT NULL;






SELECT
    c.name AS column_name,
    c.encryption_type_desc,
    cek.name AS column_encryption_key,
    cmk.name AS column_master_key,
    cmk.key_store_provider_name,
    cmk.key_path
FROM sys.columns c

INNER JOIN sys.column_encryption_keys cek
ON c.column_encryption_key_id = cek.column_encryption_key_id

INNER JOIN sys.column_encryption_key_values cekv
ON cek.column_encryption_key_id = cekv.column_encryption_key_id

INNER JOIN sys.column_master_keys cmk
ON cekv.column_master_key_id = cmk.column_master_key_id

WHERE c.object_id = OBJECT_ID('dbo.tbl_transactions_secure')
AND c.encryption_type IS NOT NULL;




SELECT TOP 5
    source_account_number,
    destination_account_name,
    session_key
FROM dbo.tbl_transactions_secure;