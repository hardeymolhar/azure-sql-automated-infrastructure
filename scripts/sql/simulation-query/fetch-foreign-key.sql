SELECT
    fk.name AS foreign_key_name,
    SCHEMA_NAME (parent_t.schema_id) AS parent_schema,
    parent_t.name AS parent_table,
    parent_c.name AS parent_column,
    SCHEMA_NAME (referenced_t.schema_id) AS referenced_schema,
    referenced_t.name AS referenced_table,
    referenced_c.name AS referenced_column
FROM
    sys.foreign_keys fk
    JOIN sys.foreign_key_columns fkc ON fk.object_id = fkc.constraint_object_id
    JOIN sys.tables parent_t ON fkc.parent_object_id = parent_t.object_id
    JOIN sys.columns parent_c ON fkc.parent_object_id = parent_c.object_id
    AND fkc.parent_column_id = parent_c.column_id
    JOIN sys.tables referenced_t ON fkc.referenced_object_id = referenced_t.object_id
    JOIN sys.columns referenced_c ON fkc.referenced_object_id = referenced_c.object_id
    AND fkc.referenced_column_id = referenced_c.column_id
WHERE
    parent_t.name = 'tbl_transactions'
    AND SCHEMA_NAME (parent_t.schema_id) = 'dbo'
ORDER BY parent_table;