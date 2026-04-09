
SELECT AVG(
    (avg_cpu_percent + avg_data_io_percent + avg_log_write_percent) / 3.0 * 100
) AS avg_resource_usage
FROM sys.dm_db_resource_stats;
