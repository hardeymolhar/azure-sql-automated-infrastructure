/*
    Azure SQL Database WhoIsActive-style snapshot

    Purpose:
    - Show currently active user requests in one database.
    - Include blocking, waits, CPU, reads/writes, elapsed time, transaction state,
      SQL text, and lock counts.

    Notes:
    - Designed for Azure SQL Database, not SQL Server instance-level monitoring.
    - Run in the user database you want to inspect.
    - Requires VIEW DATABASE STATE, or equivalent database permissions.
*/

SET NOCOUNT ON;

DECLARE @snapshot_time datetime2(3) =
    SYSUTCDATETIME();

;WITH request_locks AS
(
    SELECT
        request_session_id AS session_id,
        COUNT_BIG(*) AS lock_count,
        SUM(CASE WHEN request_status = 'WAIT' THEN 1 ELSE 0 END) AS waiting_lock_count
    FROM sys.dm_tran_locks
    GROUP BY
        request_session_id
),
session_snapshot AS
(
    SELECT
        s.session_id,
        r.request_id,
        COALESCE(r.blocking_session_id, 0) AS blocking_session_id,
        r.status AS request_status,
        s.status AS session_status,
        r.command,
        r.wait_type,
        r.wait_time AS wait_time_ms,
        r.wait_resource,
        r.last_wait_type,
        r.cpu_time AS request_cpu_ms,
        r.total_elapsed_time AS elapsed_ms,
        r.reads,
        r.writes,
        r.logical_reads,
        r.row_count,
        r.granted_query_memory,
        r.percent_complete,
        COALESCE(r.open_transaction_count, s.open_transaction_count) AS open_transaction_count,
        s.login_name,
        s.host_name,
        s.program_name,
        s.client_interface_name,
        s.login_time,
        s.last_request_start_time,
        s.last_request_end_time,
        c.client_net_address,
        c.connect_time,
        COALESCE(DB_NAME(r.database_id), DB_NAME()) AS database_name,
        r.sql_handle,
        r.statement_start_offset,
        r.statement_end_offset,
        r.plan_handle,
        CASE WHEN r.session_id IS NULL THEN 0 ELSE 1 END AS is_active_request
    FROM sys.dm_exec_sessions AS s
    LEFT JOIN sys.dm_exec_requests AS r
        ON r.session_id = s.session_id
    LEFT JOIN sys.dm_exec_connections AS c
        ON c.session_id = s.session_id
    WHERE
        s.is_user_process = 1
        AND s.session_id <> @@SPID
)
SELECT
    @snapshot_time AS snapshot_utc,
    ss.session_id,
    ss.request_id,
    ss.database_name,
    ss.is_active_request,
    ss.request_status,
    ss.session_status,
    ss.command,
    ss.blocking_session_id,
    blocker.login_name AS blocking_login_name,
    blocker.host_name AS blocking_host_name,
    blocker.program_name AS blocking_program_name,
    ss.wait_type,
    ss.last_wait_type,
    ss.wait_time_ms,
    ss.wait_resource,
    ss.elapsed_ms,
    CONVERT(decimal(18,2), ss.elapsed_ms / 1000.0) AS elapsed_seconds,
    ss.request_cpu_ms,
    ss.logical_reads,
    ss.reads,
    ss.writes,
    ss.row_count,
    ss.granted_query_memory,
    ss.percent_complete,
    ss.open_transaction_count,
    COALESCE(rl.lock_count, 0) AS lock_count,
    COALESCE(rl.waiting_lock_count, 0) AS waiting_lock_count,
    ss.login_name,
    ss.host_name,
    ss.program_name,
    ss.client_interface_name,
    ss.client_net_address,
    ss.login_time,
    ss.connect_time,
    ss.last_request_start_time,
    ss.last_request_end_time,
    CASE
        WHEN ss.sql_handle IS NULL THEN NULL
        ELSE SUBSTRING(
            st.text,
            (ss.statement_start_offset / 2) + 1,
            (
                (
                    CASE ss.statement_end_offset
                        WHEN -1 THEN DATALENGTH(st.text)
                        ELSE ss.statement_end_offset
                    END - ss.statement_start_offset
                ) / 2
            ) + 1
        )
    END AS running_statement_text,
    st.text AS batch_text,
    qp.query_plan
FROM session_snapshot AS ss
OUTER APPLY sys.dm_exec_sql_text(ss.sql_handle) AS st
OUTER APPLY sys.dm_exec_query_plan(ss.plan_handle) AS qp
LEFT JOIN request_locks AS rl
    ON rl.session_id = ss.session_id
LEFT JOIN sys.dm_exec_sessions AS blocker
    ON blocker.session_id = ss.blocking_session_id
ORDER BY
    CASE WHEN ss.blocking_session_id <> 0 THEN 0 ELSE 1 END,
    ss.is_active_request DESC,
    ss.elapsed_ms DESC,
    ss.request_cpu_ms DESC,
    ss.session_id;

/*
    Blocking chain summary
*/

;WITH blocking_edges AS
(
    SELECT
        r.session_id,
        r.blocking_session_id,
        r.wait_type,
        r.wait_time AS wait_time_ms,
        r.wait_resource,
        r.status,
        r.command
    FROM sys.dm_exec_requests AS r
    WHERE
        r.blocking_session_id <> 0
)
SELECT
    @snapshot_time AS snapshot_utc,
    be.blocking_session_id AS blocker_session_id,
    blocker.login_name AS blocker_login_name,
    blocker.host_name AS blocker_host_name,
    blocker.program_name AS blocker_program_name,
    COUNT(*) AS blocked_request_count,
    MAX(be.wait_time_ms) AS max_blocked_wait_time_ms,
    STRING_AGG(CONVERT(varchar(12), be.session_id), ',') AS blocked_session_ids
FROM blocking_edges AS be
LEFT JOIN sys.dm_exec_sessions AS blocker
    ON blocker.session_id = be.blocking_session_id
GROUP BY
    be.blocking_session_id,
    blocker.login_name,
    blocker.host_name,
    blocker.program_name
ORDER BY
    blocked_request_count DESC,
    max_blocked_wait_time_ms DESC;

/*
    Database-level resource snapshot for Azure SQL Database.
*/

SELECT TOP (15)
    end_time,
    avg_cpu_percent,
    avg_data_io_percent,
    avg_log_write_percent,
    avg_memory_usage_percent,
    xtp_storage_percent,
    max_worker_percent,
    max_session_percent,
    dtu_limit
FROM sys.dm_db_resource_stats
ORDER BY
    end_time DESC;

/*
    Current database wait stats.
*/

SELECT TOP (20)
    wait_type,
    waiting_tasks_count,
    wait_time_ms,
    signal_wait_time_ms,
    wait_time_ms - signal_wait_time_ms AS resource_wait_time_ms
FROM sys.dm_db_wait_stats
WHERE
    wait_type NOT IN
    (
        'BROKER_EVENTHANDLER',
        'BROKER_RECEIVE_WAITFOR',
        'BROKER_TASK_STOP',
        'BROKER_TO_FLUSH',
        'BROKER_TRANSMITTER',
        'CHECKPOINT_QUEUE',
        'DIRTY_PAGE_POLL',
        'HADR_FILESTREAM_IOMGR_IOCOMPLETION',
        'LAZYWRITER_SLEEP',
        'LOGMGR_QUEUE',
        'REQUEST_FOR_DEADLOCK_SEARCH',
        'SLEEP_TASK',
        'SQLTRACE_BUFFER_FLUSH',
        'XE_DISPATCHER_WAIT',
        'XE_TIMER_EVENT'
    )
ORDER BY
    wait_time_ms DESC;

/*
    Lock footprint by resource and mode.
*/

SELECT
    resource_type,
    request_mode,
    request_status,
    COUNT_BIG(*) AS lock_count
FROM sys.dm_tran_locks
GROUP BY
    resource_type,
    request_mode,
    request_status
ORDER BY
    lock_count DESC;
