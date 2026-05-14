SELECT
    session_id,
    blocking_session_id,
    status,
    wait_type,
    wait_time,
    wait_resource,
    command
FROM sys.dm_exec_requests
WHERE blocking_session_id <> 0;

SELECT TOP 20
    wait_category_desc,
    SUM(total_query_wait_time_ms) AS total_wait_ms
FROM sys.query_store_wait_stats
GROUP BY wait_category_desc
ORDER BY total_wait_ms DESC;

SELECT
    event_time,
    database_name,
    event_category,
    description
FROM sys.event_log
WHERE event_category = 'deadlock'
ORDER BY event_time DESC;


# Get the top 20 wait events by total wait time

SELECT TOP 20
    wait_type,
    waiting_tasks_count,
    wait_time_ms,
    signal_wait_time_ms
FROM sys.dm_db_wait_stats
ORDER BY wait_time_ms DESC;


SELECT
    COUNT(*) AS active_sessions
FROM sys.dm_exec_sessions
WHERE status = 'running';


SELECT
    resource_type,
    request_mode,
    request_status,
    COUNT(*) AS lock_count
FROM sys.dm_tran_locks
GROUP BY
    resource_type,
    request_mode,
    request_status
ORDER BY lock_count DESC;