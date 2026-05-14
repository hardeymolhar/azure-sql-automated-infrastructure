SELECT
    total_log_size_in_bytes / 1024 / 1024 AS total_log_mb,
    used_log_space_in_bytes / 1024 / 1024 AS used_log_mb,
    used_log_space_in_percent
FROM sys.dm_db_log_space_usage;