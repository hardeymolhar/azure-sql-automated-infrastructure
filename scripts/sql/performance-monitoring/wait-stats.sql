SELECT TOP 20
    wait_type,
    waiting_tasks_count,
    wait_time_ms,
    signal_wait_time_ms
FROM sys.dm_db_wait_stats
ORDER BY wait_time_ms DESC;