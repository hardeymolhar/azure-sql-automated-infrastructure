using System;
using System.Collections.Concurrent;
using System.Collections.Generic;
using System.Data;
using System.Threading;
using System.Threading.Tasks;

using Azure.Core;
using Azure.Identity;

using Microsoft.Data.SqlClient;
using Microsoft.Data.SqlClient.AlwaysEncrypted.AzureKeyVaultProvider;

class Program
{
    // =========================================================
    // HOTSPOT ACCOUNTS
    // =========================================================

    private static readonly string[] HotspotAccounts =
    {
        "1000000001",
        "1000000002",
        "1000000003",
        "1000000004",
        "1000000005"
    };

    // =========================================================
    // TRANSACTION TYPES
    // =========================================================

    private static readonly string[] TransactionTypes =
    {
        "TRANSFER",
        "AIRTIME",
        "BILL_PAYMENT",
        "POS",
        "REVERSAL"
    };

    // =========================================================
    // STATUSES
    // =========================================================

    private static readonly string[] Statuses =
    {
        "SUCCESS",
        "PENDING",
        "FAILED"
    };

    // =========================================================
    // USERS
    // =========================================================

    private static readonly string[] Users =
    {
        "emmanuel",
        "daniel",
        "grace",
        "victor",
        "mary"
    };

    // =========================================================
    // RETRYABLE AZURE SQL ERRORS
    // =========================================================

    private static readonly HashSet<int> RetryableErrors =
        new()
        {
            40197,
            40501,
            40613,
            49918,
            49919,
            49920,
            11001,
            10928,
            10929
        };

    // =========================================================
    // METRICS
    // =========================================================

    private static readonly ConcurrentDictionary<string, long> Metrics =
        new();

    // =========================================================
    // AZURE CREDENTIAL
    // =========================================================

    private static readonly DefaultAzureCredential Credential =
        new();

    // =========================================================
    // MAIN
    // =========================================================

    static async Task Main()
    {
        string sqlServerName =
            Environment.GetEnvironmentVariable("SQL_SERVER_NAME")
            ?? throw new Exception(
                "SQL_SERVER_NAME environment variable missing."
            );

        string databaseName =
            Environment.GetEnvironmentVariable("DATABASE_NAME")
            ?? throw new Exception(
                "DATABASE_NAME environment variable missing."
            );

        int workerCount =
            ParseEnvironmentVariable(
                "WORKER_COUNT",
                30
            );

        int reportingWorkers =
            ParseEnvironmentVariable(
                "REPORTING_WORKERS",
                5
            );

        int maxBatches =
            ParseEnvironmentVariable(
                "MAX_BATCHES",
                150
            );

        int minBatchSize =
            ParseEnvironmentVariable(
                "MIN_BATCH_SIZE",
                1000
            );

        int maxBatchSize =
            ParseEnvironmentVariable(
                "MAX_BATCH_SIZE",
                5000
            );

        int workloadDurationMinutes =
            ParseEnvironmentVariable(
                "WORKLOAD_DURATION_MINUTES",
                30
            );

        int batchDelayMilliseconds =
            ParseEnvironmentVariable(
                "BATCH_DELAY_MS",
                0
            );

        string connectionString =
            BuildConnectionString(
                sqlServerName,
                databaseName
            );

        Console.WriteLine("================================================");
        Console.WriteLine("AZURE SQL HIGH PRESSURE WORKLOAD");
        Console.WriteLine("================================================");

        Console.WriteLine($"Workers                 : {workerCount}");
        Console.WriteLine($"Reporting Workers       : {reportingWorkers}");
        Console.WriteLine($"Max Batches             : {maxBatches}");
        Console.WriteLine($"Min Batch Size          : {minBatchSize}");
        Console.WriteLine($"Max Batch Size          : {maxBatchSize}");
        Console.WriteLine($"Workload Duration (min) : {workloadDurationMinutes}");

        Console.WriteLine("================================================");

        // =========================================================
        // ALWAYS ENCRYPTED PROVIDER
        // =========================================================

        RegisterAlwaysEncryptedProvider();

        // =========================================================
        // CANCELLATION TOKEN
        // =========================================================

        using CancellationTokenSource cts =
            new();

        cts.CancelAfter(
            TimeSpan.FromMinutes(
                workloadDurationMinutes
            )
        );

        CancellationToken cancellationToken =
            cts.Token;

        // =========================================================
        // TASKS
        // =========================================================

        List<Task> tasks =
            new();

        for (int workerId = 1; workerId <= workerCount; workerId++)
        {
            int currentWorkerId =
                workerId;

            tasks.Add(
                RunTransactionalWorker(
                    currentWorkerId,
                    connectionString,
                    maxBatches,
                    minBatchSize,
                    maxBatchSize,
                    batchDelayMilliseconds,
                    cancellationToken
                )
            );
        }

        for (int i = 0; i < reportingWorkers; i++)
        {
            tasks.Add(
                RunReportingWorker(
                    connectionString,
                    cancellationToken
                )
            );
        }

        await Task.WhenAll(tasks);

        Console.WriteLine("================================================");
        Console.WriteLine("WORKLOAD COMPLETE");
        Console.WriteLine("================================================");

        foreach (var metric in Metrics)
        {
            Console.WriteLine(
                $"{metric.Key}: {metric.Value}"
            );
        }
    }

    // =========================================================
    // CONNECTION STRING
    // =========================================================

    private static string BuildConnectionString(
        string sqlServerName,
        string databaseName
    )
    {
        SqlConnectionStringBuilder builder =
            new()
            {
                DataSource =
                    $"{sqlServerName}.database.windows.net",

                InitialCatalog =
                    databaseName,

                Encrypt =
                    true,

                TrustServerCertificate =
                    false,

                Pooling =
                    true,

                MaxPoolSize =
                    200,

                MinPoolSize =
                    20,

                ConnectTimeout =
                    30,

                MultipleActiveResultSets =
                    false,

                ColumnEncryptionSetting =
                    SqlConnectionColumnEncryptionSetting.Enabled
            };

        return builder.ConnectionString;
    }

    // =========================================================
    // ALWAYS ENCRYPTED
    // =========================================================

    private static void RegisterAlwaysEncryptedProvider()
    {
        SqlColumnEncryptionAzureKeyVaultProvider provider =
            new(
                Credential
            );

        SqlConnection.RegisterColumnEncryptionKeyStoreProviders(
            new Dictionary<string,
                SqlColumnEncryptionKeyStoreProvider>
            {
                {
                    SqlColumnEncryptionAzureKeyVaultProvider.ProviderName,
                    provider
                }
            }
        );
    }

    // =========================================================
    // CREATE CONNECTION
    // =========================================================

    private static async Task<SqlConnection> CreateConnection(
        string connectionString
    )
    {
        SqlConnection conn =
            new(connectionString);

        AccessToken token =
            await Credential.GetTokenAsync(
                new TokenRequestContext(
                    new[]
                    {
                        "https://database.windows.net/.default"
                    }
                )
            );

        conn.AccessToken =
            token.Token;

        await conn.OpenAsync();

        return conn;
    }

    // =========================================================
    // TRANSACTION WORKER
    // =========================================================

    private static async Task RunTransactionalWorker(
        int workerId,
        string connectionString,
        int maxBatches,
        int minBatchSize,
        int maxBatchSize,
        int batchDelayMilliseconds,
        CancellationToken cancellationToken
    )
    {
        Random random =
            new(Guid.NewGuid().GetHashCode());

        for (
            int batchNumber = 1;
            batchNumber <= maxBatches;
            batchNumber++
        )
        {
            if (cancellationToken.IsCancellationRequested)
            {
                return;
            }

            try
            {
                await ExecuteWithRetry(
                    async () =>
                    {
                        using SqlConnection conn =
                            await CreateConnection(
                                connectionString
                            );

                        int batchSize =
                            random.Next(
                                minBatchSize,
                                maxBatchSize + 1
                            );

                        Console.WriteLine(
                            $"[Worker {workerId}] Starting batch {batchNumber} with {batchSize} rows"
                        );

                        using SqlTransaction transaction =
                            (SqlTransaction)
                                await conn.BeginTransactionAsync(
                                    IsolationLevel.ReadCommitted
                                );

                        try
                        {
                            // =========================================================
                            // INSERTS
                            // =========================================================

                            for (int row = 0; row < batchSize; row++)
                            {
                                using SqlCommand cmd =
                                    BuildInsertCommand(
                                        conn,
                                        transaction,
                                        random
                                    );

                                cmd.CommandTimeout =
                                    120;

                                await cmd.ExecuteNonQueryAsync();

                                Metrics.AddOrUpdate(
                                    "Inserted Rows",
                                    1,
                                    (_, value) => value + 1
                                );

                                if (row % 500 == 0)
                                {
                                    await Task.Delay(
                                        random.Next(5, 20)
                                    );
                                }
                            }

                            // =========================================================
                            // HOTSPOT UPDATE CONTENTION
                            // =========================================================

                            using SqlCommand updateCmd =
                                BuildUpdateCommand(
                                    conn,
                                    transaction,
                                    random
                                );

                            updateCmd.CommandTimeout =
                                120;

                            int updatedRows =
                                await updateCmd.ExecuteNonQueryAsync();

                            Metrics.AddOrUpdate(
                                "Updated Rows",
                                updatedRows,
                                (_, value) => value + updatedRows
                            );

                            // =========================================================
                            // DEADLOCK GENERATION
                            // =========================================================

                            await GenerateDeadlockPattern(
                                conn,
                                transaction,
                                random
                            );

                            // =========================================================
                            // SOFT DELETE PRESSURE
                            // =========================================================

                            using SqlCommand deleteCmd =
                                BuildSoftDeleteCommand(
                                    conn,
                                    transaction,
                                    random
                                );

                            deleteCmd.CommandTimeout =
                                120;

                            int deletedRows =
                                await deleteCmd.ExecuteNonQueryAsync();

                            Metrics.AddOrUpdate(
                                "Soft Deleted Rows",
                                deletedRows,
                                (_, value) => value + deletedRows
                            );

                            // =========================================================
                            // HOLD LOCKS
                            // =========================================================

                            using SqlCommand waitCmd =
                                new(
                                    "WAITFOR DELAY '00:00:01';",
                                    conn,
                                    transaction
                                );

                            waitCmd.CommandTimeout =
                                120;

                            await waitCmd.ExecuteNonQueryAsync();

                            await transaction.CommitAsync();

                            Metrics.AddOrUpdate(
                                "Committed Transactions",
                                1,
                                (_, value) => value + 1
                            );

                            Console.WriteLine(
                                $"[Worker {workerId}] Committed batch {batchNumber}"
                            );
                        }
                        catch (Exception ex)
                        {
                            Metrics.AddOrUpdate(
                                "Transaction Errors",
                                1,
                                (_, value) => value + 1
                            );

                            Console.WriteLine(
                                $"[Worker {workerId}] ERROR: {ex.Message}"
                            );

                            try
                            {
                                await transaction.RollbackAsync();
                            }
                            catch
                            {
                            }
                        }
                    }
                );
            }
            catch (Exception ex)
            {
                Console.WriteLine(
                    $"[Worker {workerId}] FATAL: {ex.Message}"
                );
            }

            if (batchDelayMilliseconds > 0)
            {
                await Task.Delay(
                    batchDelayMilliseconds
                );
            }
        }
    }

    // =========================================================
    // REPORTING WORKER
    // =========================================================

    private static async Task RunReportingWorker(
        string connectionString,
        CancellationToken cancellationToken
    )
    {
        while (!cancellationToken.IsCancellationRequested)
        {
            try
            {
                using SqlConnection conn =
                    await CreateConnection(
                        connectionString
                    );

                string reportingSql =
                @"
                SELECT TOP (100)
                    transaction_type,
                    transaction_final_status,
                    source_account_number,
                    COUNT(*) AS total_transactions,
                    SUM(amount) AS total_amount,
                    AVG(amount) AS average_amount
                FROM dbo.tbl_transactions_secure
                WHERE created_on >
                    DATEADD(MINUTE, -30, SYSUTCDATETIME())
                GROUP BY
                    transaction_type,
                    transaction_final_status,
                    source_account_number
                ORDER BY total_amount DESC;
                ";

                using SqlCommand cmd =
                    new(reportingSql, conn);

                cmd.CommandTimeout =
                    120;

                using SqlDataReader reader =
                    await cmd.ExecuteReaderAsync();

                while (await reader.ReadAsync())
                {
                }

                Metrics.AddOrUpdate(
                    "Reporting Queries",
                    1,
                    (_, value) => value + 1
                );

                Console.WriteLine(
                    "[REPORTING] Query completed."
                );
            }
            catch (Exception ex)
            {
                Metrics.AddOrUpdate(
                    "Reporting Errors",
                    1,
                    (_, value) => value + 1
                );

                Console.WriteLine(
                    $"[REPORTING] ERROR: {ex.Message}"
                );
            }

            await Task.Delay(500);
        }
    }

    // =========================================================
    // RETRY EXECUTION
    // =========================================================

    private static async Task ExecuteWithRetry(
        Func<Task> operation
    )
    {
        int retries =
            5;

        for (int attempt = 1; attempt <= retries; attempt++)
        {
            try
            {
                await operation();

                return;
            }
            catch (SqlException ex)
                when (RetryableErrors.Contains(ex.Number))
            {
                Metrics.AddOrUpdate(
                    "Throttle Events",
                    1,
                    (_, value) => value + 1
                );

                Console.WriteLine(
                    $"Retryable SQL error {ex.Number}. Attempt {attempt}"
                );

                await Task.Delay(
                    attempt * 3000
                );
            }
        }
    }

    // =========================================================
    // DEADLOCK GENERATION
    // =========================================================

    private static async Task GenerateDeadlockPattern(
        SqlConnection conn,
        SqlTransaction transaction,
        Random random
    )
    {
        bool reverseOrder =
            random.Next(100) < 50;

        string sql =
            reverseOrder
                ? @"
                    UPDATE dbo.tbl_transactions_secure
                    SET charged_fee = charged_fee + 1
                    WHERE transaction_id = 1;

                    WAITFOR DELAY '00:00:01';

                    UPDATE dbo.tbl_transactions_secure
                    SET charged_fee = charged_fee + 1
                    WHERE transaction_id = 2;
                "
                : @"
                    UPDATE dbo.tbl_transactions_secure
                    SET charged_fee = charged_fee + 1
                    WHERE transaction_id = 2;

                    WAITFOR DELAY '00:00:01';

                    UPDATE dbo.tbl_transactions_secure
                    SET charged_fee = charged_fee + 1
                    WHERE transaction_id = 1;
                ";

        using SqlCommand cmd =
            new(sql, conn, transaction);

        cmd.CommandTimeout =
            120;

        await cmd.ExecuteNonQueryAsync();
    }

    // =========================================================
    // INSERT COMMAND
    // =========================================================

    private static SqlCommand BuildInsertCommand(
        SqlConnection conn,
        SqlTransaction transaction,
        Random random
    )
    {
        string sql =
        @"
        INSERT INTO dbo.tbl_transactions_secure
        (
            transaction_sub_type,
            transaction_type,
            amount,
            charged_fee,
            currency_code,
            source_account_number,
            destination_account_number,
            destination_account_name,
            destination_bank_code,
            destination_bank_name,
            transaction_reference,
            transaction_external_reference,
            transaction_posting_reference,
            request_transaction_id,
            transaction_final_status,
            transaction_request_status,
            session_key,
            recharge_pin,
            electricity_token,
            user_name,
            created_by,
            modified_by,
            created_on,
            modified_on,
            transaction_request_date,
            transaction_response_date,
            reversed,
            vat_inclusive
        )
        VALUES
        (
            @transaction_sub_type,
            @transaction_type,
            @amount,
            @charged_fee,
            @currency_code,
            @source_account_number,
            @destination_account_number,
            @destination_account_name,
            @destination_bank_code,
            @destination_bank_name,
            @transaction_reference,
            @transaction_external_reference,
            @transaction_posting_reference,
            @request_transaction_id,
            @transaction_final_status,
            @transaction_request_status,
            @session_key,
            @recharge_pin,
            @electricity_token,
            @user_name,
            @created_by,
            @modified_by,
            @created_on,
            @modified_on,
            @transaction_request_date,
            @transaction_response_date,
            @reversed,
            @vat_inclusive
        );
        ";

        SqlCommand cmd =
            new(sql, conn, transaction);

        DateTime now =
            DateTime.UtcNow;

        decimal amount =
            Math.Round(
                (decimal)(random.NextDouble() * 1000000),
                2
            );

        decimal fee =
            Math.Round(
                amount * 0.0075m,
                2
            );

        string sourceAccount =
            random.Next(100) <= 75
                ? HotspotAccounts[
                    random.Next(HotspotAccounts.Length)
                ]
                : random.NextInt64(
                    1000000000,
                    9999999999
                ).ToString();

        cmd.Parameters.Add(
            "@transaction_sub_type",
            SqlDbType.NVarChar
        ).Value = GetWeightedTransactionType(random);

        cmd.Parameters.Add(
            "@transaction_type",
            SqlDbType.NVarChar
        ).Value = GetWeightedTransactionType(random);

        cmd.Parameters.Add(
            "@amount",
            SqlDbType.Decimal
        ).Value = amount;

        cmd.Parameters.Add(
            "@charged_fee",
            SqlDbType.Decimal
        ).Value = fee;

        cmd.Parameters.Add(
            "@currency_code",
            SqlDbType.NVarChar
        ).Value = "NGN";

        cmd.Parameters.Add(
            "@source_account_number",
            SqlDbType.NVarChar
        ).Value = sourceAccount;

        cmd.Parameters.Add(
            "@destination_account_number",
            SqlDbType.NVarChar
        ).Value = sourceAccount;

        cmd.Parameters.Add(
            "@destination_account_name",
            SqlDbType.NVarChar
        ).Value = "John Doe";

        cmd.Parameters.Add(
            "@destination_bank_code",
            SqlDbType.NVarChar
        ).Value = "044";

        cmd.Parameters.Add(
            "@destination_bank_name",
            SqlDbType.NVarChar
        ).Value = "Access Bank";

        cmd.Parameters.Add(
            "@transaction_reference",
            SqlDbType.UniqueIdentifier
        ).Value = Guid.NewGuid();

        cmd.Parameters.Add(
            "@transaction_external_reference",
            SqlDbType.UniqueIdentifier
        ).Value = Guid.NewGuid();

        cmd.Parameters.Add(
            "@transaction_posting_reference",
            SqlDbType.UniqueIdentifier
        ).Value = Guid.NewGuid();

        cmd.Parameters.Add(
            "@request_transaction_id",
            SqlDbType.UniqueIdentifier
        ).Value = Guid.NewGuid();

        cmd.Parameters.Add(
            "@transaction_final_status",
            SqlDbType.NVarChar
        ).Value = Statuses[
            random.Next(Statuses.Length)
        ];

        cmd.Parameters.Add(
            "@transaction_request_status",
            SqlDbType.NVarChar
        ).Value = Statuses[
            random.Next(Statuses.Length)
        ];

        cmd.Parameters.Add(
            "@session_key",
            SqlDbType.NVarChar
        ).Value = Guid.NewGuid().ToString();

        cmd.Parameters.Add(
            "@recharge_pin",
            SqlDbType.NVarChar
        ).Value = random.Next(1000, 9999).ToString();

        cmd.Parameters.Add(
            "@electricity_token",
            SqlDbType.NVarChar
        ).Value = random.NextInt64(
            100000000000,
            999999999999
        ).ToString();

        cmd.Parameters.Add(
            "@user_name",
            SqlDbType.NVarChar
        ).Value = Users[
            random.Next(Users.Length)
        ];

        cmd.Parameters.Add(
            "@created_by",
            SqlDbType.NVarChar
        ).Value = "concurrency-worker";

        cmd.Parameters.Add(
            "@modified_by",
            SqlDbType.NVarChar
        ).Value = "concurrency-worker";

        cmd.Parameters.Add(
            "@created_on",
            SqlDbType.DateTime2
        ).Value = now;

        cmd.Parameters.Add(
            "@modified_on",
            SqlDbType.DateTime2
        ).Value = now;

        cmd.Parameters.Add(
            "@transaction_request_date",
            SqlDbType.DateTime2
        ).Value = now;

        cmd.Parameters.Add(
            "@transaction_response_date",
            SqlDbType.DateTime2
        ).Value = now;

        cmd.Parameters.Add(
            "@reversed",
            SqlDbType.Bit
        ).Value = false;

        cmd.Parameters.Add(
            "@vat_inclusive",
            SqlDbType.Bit
        ).Value = true;

        return cmd;
    }

    // =========================================================
    // UPDATE COMMAND
    // =========================================================

    private static SqlCommand BuildUpdateCommand(
        SqlConnection conn,
        SqlTransaction transaction,
        Random random
    )
    {
        string sql =
        @"
        UPDATE TOP (@update_limit)
            dbo.tbl_transactions_secure
        SET
            charged_fee = charged_fee + @fee_increment,
            modified_on = SYSUTCDATETIME(),
            modified_by = 'parallel-update'
        WHERE
            source_account_number = @hotspot_account
            AND reversed = 0;

        WAITFOR DELAY '00:00:01';
        ";

        SqlCommand cmd =
            new(sql, conn, transaction);

        cmd.Parameters.Add(
            "@update_limit",
            SqlDbType.Int
        ).Value =
            random.Next(5000, 15000);

        cmd.Parameters.Add(
            "@fee_increment",
            SqlDbType.Decimal
        ).Value =
            random.Next(10, 100);

        cmd.Parameters.Add(
            "@hotspot_account",
            SqlDbType.NVarChar
        ).Value =
            HotspotAccounts[
                random.Next(HotspotAccounts.Length)
            ];

        return cmd;
    }

    // =========================================================
    // SOFT DELETE
    // =========================================================

    private static SqlCommand BuildSoftDeleteCommand(
        SqlConnection conn,
        SqlTransaction transaction,
        Random random
    )
    {
        string sql =
        @"
        UPDATE TOP (@delete_limit)
            dbo.tbl_transactions_secure
        SET
            reversed = 1,
            modified_on = SYSUTCDATETIME()
        WHERE
            source_account_number = @hotspot_account
            AND reversed = 0
            AND created_on <
                DATEADD(MINUTE, -5, SYSUTCDATETIME());

        WAITFOR DELAY '00:00:01';
        ";

        SqlCommand cmd =
            new(sql, conn, transaction);

        cmd.Parameters.Add(
            "@delete_limit",
            SqlDbType.Int
        ).Value =
            random.Next(2000, 8000);

        cmd.Parameters.Add(
            "@hotspot_account",
            SqlDbType.NVarChar
        ).Value =
            HotspotAccounts[
                random.Next(HotspotAccounts.Length)
            ];

        return cmd;
    }

    // =========================================================
    // WEIGHTED TRANSACTION TYPE
    // =========================================================

    private static string GetWeightedTransactionType(
        Random random
    )
    {
        int value =
            random.Next(100);

        if (value < 60)
            return "TRANSFER";

        if (value < 80)
            return "POS";

        if (value < 90)
            return "AIRTIME";

        return "REVERSAL";
    }

    // =========================================================
    // ENV VARIABLE PARSER
    // =========================================================

    private static int ParseEnvironmentVariable(
        string variableName,
        int defaultValue
    )
    {
        return int.TryParse(
            Environment.GetEnvironmentVariable(
                variableName
            ),
            out int parsedValue
        )
            ? parsedValue
            : defaultValue;
    }
}

