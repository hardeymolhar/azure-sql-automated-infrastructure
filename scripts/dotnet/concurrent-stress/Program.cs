
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
    private static readonly string[] TransactionTypes =
    {
        "TRANSFER",
        "AIRTIME",
        "BILL_PAYMENT",
        "POS",
        "REVERSAL"
    };

    private static readonly string[] Statuses =
    {
        "SUCCESS",
        "PENDING",
        "FAILED"
    };

    private static readonly string[] Users =
    {
        "emmanuel",
        "daniel",
        "grace",
        "victor",
        "mary"
    };

    private static readonly HashSet<int> RetryableErrors =
        new()
        {
            1205,
            40197,
            40501,
            40613,
            49918,
            49919,
            49920,
            10928,
            10929,
            11001
        };

    private static readonly ConcurrentDictionary<string, int> Metrics =
        new ConcurrentDictionary<string, int>();

    static async Task Main()
    {
        string server =
            $"{Environment.GetEnvironmentVariable("SQL_SERVER_NAME")}.database.windows.net";

        string database =
            Environment.GetEnvironmentVariable("DATABASE_NAME")
            ?? throw new Exception(
                "DATABASE_NAME environment variable is missing."
            );

        int workerCount =
            int.TryParse(
                Environment.GetEnvironmentVariable("WORKER_COUNT"),
                out int parsedWorkerCount
            )
                ? parsedWorkerCount
                : 40;

        int reportingWorkerCount =
            int.TryParse(
                Environment.GetEnvironmentVariable("REPORTING_WORKERS"),
                out int parsedReportingWorkerCount
            )
                ? parsedReportingWorkerCount
                : 12;

        int deadlockWorkerCount =
            int.TryParse(
                Environment.GetEnvironmentVariable("DEADLOCK_WORKERS"),
                out int parsedDeadlockWorkerCount
            )
                ? parsedDeadlockWorkerCount
                : 6;

        int sessionHolderCount =
            int.TryParse(
                Environment.GetEnvironmentVariable("SESSION_HOLDER_COUNT"),
                out int parsedSessionHolderCount
            )
                ? parsedSessionHolderCount
                : 220;

        int maxBatches =
            int.TryParse(
                Environment.GetEnvironmentVariable("MAX_BATCHES"),
                out int parsedMaxBatches
            )
                ? parsedMaxBatches
                : 0;

        int minBatchSize =
            int.TryParse(
                Environment.GetEnvironmentVariable("MIN_BATCH_SIZE"),
                out int parsedMinBatchSize
            )
                ? parsedMinBatchSize
                : 750;

        int maxBatchSize =
            int.TryParse(
                Environment.GetEnvironmentVariable("MAX_BATCH_SIZE"),
                out int parsedMaxBatchSize
            )
                ? parsedMaxBatchSize
                : 2500;

        int batchDelayMilliseconds =
            int.TryParse(
                Environment.GetEnvironmentVariable("BATCH_DELAY_MS"),
                out int parsedBatchDelayMilliseconds
            )
                ? parsedBatchDelayMilliseconds
                : 0;

        int workloadDurationMinutes =
            int.TryParse(
                Environment.GetEnvironmentVariable("WORKLOAD_DURATION_MINUTES"),
                out int parsedWorkloadDurationMinutes
            )
                ? parsedWorkloadDurationMinutes
                : 30;

        Console.WriteLine("================================================");
        Console.WriteLine("AZURE SQL CONCURRENT STRESS WORKLOAD");
        Console.WriteLine("================================================");
        Console.WriteLine($"Workers           : {workerCount}");
        Console.WriteLine($"Reporting Workers : {reportingWorkerCount}");
        Console.WriteLine($"Deadlock Workers  : {deadlockWorkerCount}");
        Console.WriteLine($"Session Holders   : {sessionHolderCount}");
        Console.WriteLine(
            maxBatches > 0
                ? $"Max Batches       : {maxBatches}"
                : "Max Batches       : duration limited"
        );
        Console.WriteLine($"Min Batch Size    : {minBatchSize}");
        Console.WriteLine($"Max Batch Size    : {maxBatchSize}");
        Console.WriteLine($"Batch Delay (ms)  : {batchDelayMilliseconds}");
        Console.WriteLine($"Duration (min)    : {workloadDurationMinutes}");
        Console.WriteLine("================================================");

        var credential =
            new DefaultAzureCredential();

        SqlColumnEncryptionAzureKeyVaultProvider akvProvider =
            new SqlColumnEncryptionAzureKeyVaultProvider(
                credential
            );

        SqlConnection.RegisterColumnEncryptionKeyStoreProviders(
            new Dictionary<string,
                SqlColumnEncryptionKeyStoreProvider>
            {
                {
                    SqlColumnEncryptionAzureKeyVaultProvider.ProviderName,
                    akvProvider
                }
            }
        );

        AccessToken token =
            await credential.GetTokenAsync(
                new TokenRequestContext(
                    new[]
                    {
                        "https://database.windows.net/.default"
                    }
                )
            );

        string connectionString =
            $"Server={server};" +
            $"Database={database};" +
            $"Encrypt=True;" +
            $"TrustServerCertificate=False;" +
            $"Column Encryption Setting=Enabled;" +
            $"Connection Timeout=30;" +
            $"Pooling=true;" +
            $"Max Pool Size=400;" +
            $"Min Pool Size=50;" +
            $"MultipleActiveResultSets=False;";

        using CancellationTokenSource cancellation =
            new(
                TimeSpan.FromMinutes(
                    workloadDurationMinutes
                )
            );

        CancellationToken cancellationToken =
            cancellation.Token;

        List<Task> tasks = new();

        for (int workerId = 1; workerId <= workerCount; workerId++)
        {
            int currentWorkerId = workerId;

            tasks.Add(
                RunTransactionalWorker(
                    currentWorkerId,
                    connectionString,
                    token.Token,
                    maxBatches,
                    minBatchSize,
                    maxBatchSize,
                    batchDelayMilliseconds,
                    cancellationToken
                )
            );
        }

        for (int workerId = 1; workerId <= reportingWorkerCount; workerId++)
        {
            tasks.Add(
                RunReportingWorker(
                    workerId,
                    connectionString,
                    token.Token,
                    cancellationToken
                )
            );
        }

        for (int workerId = 1; workerId <= deadlockWorkerCount; workerId++)
        {
            tasks.Add(
                RunDeadlockWorker(
                    workerId,
                    connectionString,
                    token.Token,
                    cancellationToken
                )
            );
        }

        for (int workerId = 1; workerId <= sessionHolderCount; workerId++)
        {
            tasks.Add(
                HoldSessionWorker(
                    workerId,
                    connectionString,
                    token.Token,
                    cancellationToken
                )
            );
        }

        try
        {
            await Task.WhenAll(tasks);
        }
        catch (OperationCanceledException)
        {
        }

        Console.WriteLine("================================================");
        Console.WriteLine("WORKLOAD COMPLETE");
        Console.WriteLine("================================================");

        foreach (var metric in Metrics)
        {
            Console.WriteLine($"{metric.Key}: {metric.Value}");
        }
    }

    private static async Task RunTransactionalWorker(
        int workerId,
        string connectionString,
        string accessToken,
        int maxBatches,
        int minBatchSize,
        int maxBatchSize,
        int batchDelayMilliseconds,
        CancellationToken cancellationToken
    )
    {
        Random random =
            new Random(Guid.NewGuid().GetHashCode());

        for (
            int batchNumber = 1;
            !cancellationToken.IsCancellationRequested &&
                (maxBatches <= 0 || batchNumber <= maxBatches);
            batchNumber++
        )
        {
            using SqlConnection conn =
                new SqlConnection(connectionString);

            conn.AccessToken = accessToken;

            await conn.OpenAsync(cancellationToken);

            int batchSize =
                random.Next(minBatchSize, maxBatchSize + 1);

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
                for (int row = 0; row < batchSize; row++)
                {
                    using SqlCommand cmd =
                        BuildInsertCommand(
                            conn,
                            transaction,
                            random
                        );

                    await cmd.ExecuteNonQueryAsync(cancellationToken);

                    Metrics.AddOrUpdate(
                        "Inserted Rows",
                        1,
                        (_, existing) => existing + 1
                    );

                    if (row % 250 == 0)
                    {
                        await Task.Delay(
                            random.Next(5, 25),
                            cancellationToken
                        );
                    }
                }

                using SqlCommand updateCmd =
                    BuildRandomizedUpdateCommand(
                        conn,
                        transaction,
                        random
                    );

                int updatedRows =
                    await updateCmd.ExecuteNonQueryAsync(cancellationToken);

                Metrics.AddOrUpdate(
                    "Updated Rows",
                    updatedRows,
                    (_, existing) => existing + updatedRows
                );

                Console.WriteLine(
                    $"[Worker {workerId}] Updated rows: {updatedRows}"
                );

                using SqlCommand deleteCmd =
                    BuildDeleteCommand(
                        conn,
                        transaction,
                        random
                    );

                int deletedRows =
                    await deleteCmd.ExecuteNonQueryAsync(cancellationToken);

                Metrics.AddOrUpdate(
                    "Deleted Rows",
                    deletedRows,
                    (_, existing) => existing + deletedRows
                );

                Console.WriteLine(
                    $"[Worker {workerId}] Deleted rows: {deletedRows}"
                );

                await Task.Delay(
                    random.Next(1500, 5000),
                    cancellationToken
                );

                await transaction.CommitAsync(cancellationToken);

                Console.WriteLine(
                    $"[Worker {workerId}] Committed batch {batchNumber}"
                );
            }
            catch (Exception ex)
            {
                Console.WriteLine(
                    $"[Worker {workerId}] ERROR: {ex.Message}"
                );

                try
                {
                    await transaction.RollbackAsync(cancellationToken);
                }
                catch
                {
                }
            }

            if (batchDelayMilliseconds > 0)
            {
                await Task.Delay(
                    batchDelayMilliseconds,
                    cancellationToken
                );
            }
        }
    }

    private static async Task RunReportingWorker(
        int workerId,
        string connectionString,
        string accessToken,
        CancellationToken cancellationToken
    )
    {
        while (!cancellationToken.IsCancellationRequested)
        {
            try
            {
                using SqlConnection conn =
                    new SqlConnection(connectionString);

                conn.AccessToken = accessToken;

                await conn.OpenAsync();

                string reportingSql =
                @"
                SELECT TOP (50)
                    transaction_type,
                    transaction_final_status,
                    COUNT(*) AS total_transactions,
                    SUM(amount) AS total_amount,
                    AVG(amount) AS average_amount
                FROM dbo.tbl_transactions_secure
                WHERE created_on > DATEADD(MINUTE, -30, SYSUTCDATETIME())
                GROUP BY
                    transaction_type,
                    transaction_final_status
                ORDER BY total_amount DESC;
                ";

                using SqlCommand reportCmd =
                    new SqlCommand(reportingSql, conn);

                reportCmd.CommandTimeout =
                    120;

                using SqlDataReader reader =
                    await reportCmd.ExecuteReaderAsync(cancellationToken);

                int rows = 0;

                while (await reader.ReadAsync(cancellationToken))
                {
                    rows++;
                }

                Console.WriteLine(
                    $"[REPORTING {workerId}] Completed reporting query with {rows} result rows"
                );

                Metrics.AddOrUpdate(
                    "Reporting Queries",
                    1,
                    (_, existing) => existing + 1
                );
            }
            catch (Exception ex)
            {
                Console.WriteLine(
                    $"[REPORTING] ERROR: {ex.Message}"
                );
            }

            await Task.Delay(
                250,
                cancellationToken
            );
        }
    }

    private static async Task RunDeadlockWorker(
        int workerId,
        string connectionString,
        string accessToken,
        CancellationToken cancellationToken
    )
    {
        bool reverseOrder =
            workerId % 2 == 0;

        while (!cancellationToken.IsCancellationRequested)
        {
            try
            {
                using SqlConnection conn =
                    new SqlConnection(connectionString);

                conn.AccessToken = accessToken;

                await conn.OpenAsync(cancellationToken);

                using SqlTransaction transaction =
                    (SqlTransaction)await conn.BeginTransactionAsync(
                        IsolationLevel.Serializable,
                        cancellationToken
                    );

                try
                {
                    using SqlCommand cmd =
                        BuildDeadlockCommand(
                            conn,
                            transaction,
                            reverseOrder
                        );

                    cmd.CommandTimeout =
                        30;

                    await cmd.ExecuteNonQueryAsync(cancellationToken);

                    await transaction.CommitAsync(cancellationToken);
                }
                catch (SqlException ex)
                    when (ex.Number == 1205)
                {
                    Metrics.AddOrUpdate(
                        "Deadlocks",
                        1,
                        (_, existing) => existing + 1
                    );

                    Console.WriteLine(
                        $"[DEADLOCK {workerId}] Deadlock victim generated."
                    );
                }
                catch
                {
                    try
                    {
                        await transaction.RollbackAsync(cancellationToken);
                    }
                    catch
                    {
                    }

                    throw;
                }
            }
            catch (OperationCanceledException)
            {
                return;
            }
            catch (Exception ex)
            {
                Console.WriteLine(
                    $"[DEADLOCK {workerId}] ERROR: {ex.Message}"
                );
            }

            await Task.Delay(
                100,
                cancellationToken
            );
        }
    }

    private static async Task HoldSessionWorker(
        int workerId,
        string connectionString,
        string accessToken,
        CancellationToken cancellationToken
    )
    {
        try
        {
            using SqlConnection conn =
                new SqlConnection(connectionString);

            conn.AccessToken =
                accessToken;

            await conn.OpenAsync(cancellationToken);

            Metrics.AddOrUpdate(
                "Held Sessions",
                1,
                (_, existing) => existing + 1
            );

            Console.WriteLine(
                $"[SESSION {workerId}] Holding session open."
            );

            while (!cancellationToken.IsCancellationRequested)
            {
                using SqlCommand cmd =
                    new SqlCommand(
                        "SELECT 1;",
                        conn
                    );

                await cmd.ExecuteScalarAsync(cancellationToken);

                await Task.Delay(
                    30000,
                    cancellationToken
                );
            }
        }
        catch (OperationCanceledException)
        {
        }
    }

    private static SqlCommand BuildDeadlockCommand(
        SqlConnection conn,
        SqlTransaction transaction,
        bool reverseOrder
    )
    {
        string sql =
            reverseOrder
                ? @"
                    EXEC sp_getapplock
                        @Resource = 'azure-sql-stress-lock-b',
                        @LockMode = 'Exclusive',
                        @LockOwner = 'Transaction',
                        @LockTimeout = 10000;

                    WAITFOR DELAY '00:00:02';

                    EXEC sp_getapplock
                        @Resource = 'azure-sql-stress-lock-a',
                        @LockMode = 'Exclusive',
                        @LockOwner = 'Transaction',
                        @LockTimeout = 10000;
                "
                : @"
                    EXEC sp_getapplock
                        @Resource = 'azure-sql-stress-lock-a',
                        @LockMode = 'Exclusive',
                        @LockOwner = 'Transaction',
                        @LockTimeout = 10000;

                    WAITFOR DELAY '00:00:02';

                    EXEC sp_getapplock
                        @Resource = 'azure-sql-stress-lock-b',
                        @LockMode = 'Exclusive',
                        @LockOwner = 'Transaction',
                        @LockTimeout = 10000;
                ";

        return new SqlCommand(
            sql,
            conn,
            transaction
        );
    }

    private static SqlCommand BuildInsertCommand(
        SqlConnection conn,
        SqlTransaction transaction,
        Random random
    )
    {
        string insertSql =
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
        )
        ";

        SqlCommand cmd =
            new SqlCommand(
                insertSql,
                conn,
                transaction,
                SqlCommandColumnEncryptionSetting.Enabled
            );

        DateTime now = DateTime.UtcNow;

        string transactionType =
            TransactionTypes[
                random.Next(TransactionTypes.Length)
            ];

        decimal amount =
            Math.Round(
                (decimal)(random.NextDouble() * 1000000),
                2
            );

        decimal fee =
            Math.Round(amount * 0.0075m, 2);

        cmd.Parameters.Add("@transaction_sub_type", SqlDbType.NVarChar, 31).Value = transactionType;
        cmd.Parameters.Add("@transaction_type", SqlDbType.NVarChar, 50).Value = transactionType;

        SqlParameter amountParameter =
            cmd.Parameters.Add("@amount", SqlDbType.Decimal);

        amountParameter.Precision = 19;
        amountParameter.Scale = 2;
        amountParameter.Value = amount;

        SqlParameter feeParameter =
            cmd.Parameters.Add("@charged_fee", SqlDbType.Decimal);

        feeParameter.Precision = 19;
        feeParameter.Scale = 2;
        feeParameter.Value = fee;

        cmd.Parameters.Add("@currency_code", SqlDbType.Char, 3).Value = "NGN";

        cmd.Parameters.Add(
            new SqlParameter("@source_account_number", SqlDbType.NVarChar, 20)
            {
                ForceColumnEncryption = true,
                Value = random.NextInt64(1000000000, 9999999999).ToString()
            });

        cmd.Parameters.Add(
            new SqlParameter("@destination_account_number", SqlDbType.NVarChar, 20)
            {
                ForceColumnEncryption = true,
                Value = random.NextInt64(1000000000, 9999999999).ToString()
            });

        cmd.Parameters.Add(
            new SqlParameter("@destination_account_name", SqlDbType.NVarChar, 150)
            {
                ForceColumnEncryption = true,
                Value = "John Doe"
            });

        cmd.Parameters.Add("@destination_bank_code", SqlDbType.VarChar, 10).Value = "044";
        cmd.Parameters.Add("@destination_bank_name", SqlDbType.NVarChar, 100).Value = "Access Bank";
        cmd.Parameters.Add("@transaction_reference", SqlDbType.VarChar, 100).Value = Guid.NewGuid().ToString();
        cmd.Parameters.Add("@transaction_external_reference", SqlDbType.VarChar, 100).Value = Guid.NewGuid().ToString();
        cmd.Parameters.Add("@transaction_posting_reference", SqlDbType.VarChar, 100).Value = Guid.NewGuid().ToString();
        cmd.Parameters.Add("@request_transaction_id", SqlDbType.VarChar, 100).Value = Guid.NewGuid().ToString();
        cmd.Parameters.Add("@transaction_final_status", SqlDbType.VarChar, 50).Value = Statuses[random.Next(Statuses.Length)];
        cmd.Parameters.Add("@transaction_request_status", SqlDbType.VarChar, 50).Value = Statuses[random.Next(Statuses.Length)];

        cmd.Parameters.Add(
            new SqlParameter("@session_key", SqlDbType.NVarChar, 255)
            {
                ForceColumnEncryption = true,
                Value = Guid.NewGuid().ToString()
            });

        cmd.Parameters.Add(
            new SqlParameter("@recharge_pin", SqlDbType.NVarChar, 50)
            {
                ForceColumnEncryption = true,
                Value = random.Next(1000, 9999).ToString()
            });

        cmd.Parameters.Add(
            new SqlParameter("@electricity_token", SqlDbType.NVarChar, 100)
            {
                ForceColumnEncryption = true,
                Value = random.NextInt64(100000000000, 999999999999).ToString()
            });

        cmd.Parameters.Add("@user_name", SqlDbType.NVarChar, 50).Value = Users[random.Next(Users.Length)];
        cmd.Parameters.Add("@created_by", SqlDbType.NVarChar, 100).Value = "concurrency-worker";
        cmd.Parameters.Add("@modified_by", SqlDbType.NVarChar, 100).Value = "concurrency-worker";
        cmd.Parameters.Add("@created_on", SqlDbType.DateTime2).Value = now;
        cmd.Parameters.Add("@modified_on", SqlDbType.DateTime2).Value = now;
        cmd.Parameters.Add("@transaction_request_date", SqlDbType.DateTime2).Value = now;
        cmd.Parameters.Add("@transaction_response_date", SqlDbType.DateTime2).Value = now;
        cmd.Parameters.Add("@reversed", SqlDbType.Bit).Value = false;
        cmd.Parameters.Add("@vat_inclusive", SqlDbType.Bit).Value = true;

        return cmd;
    }

    private static SqlCommand BuildRandomizedUpdateCommand(
        SqlConnection conn,
        SqlTransaction transaction,
        Random random
    )
    {
        string updateSql =
        @"
        UPDATE TOP (@update_limit)
            dbo.tbl_transactions_secure
        SET
            charged_fee = charged_fee + @fee_increment,
            modified_on = SYSUTCDATETIME(),
            modified_by = 'parallel-update'
        WHERE
            transaction_final_status = @status
            AND amount > @minimum_amount
            AND reversed = 0;
        ";

        SqlCommand cmd =
            new SqlCommand(
                updateSql,
                conn,
                transaction,
                SqlCommandColumnEncryptionSetting.Enabled
            );

        cmd.Parameters.Add("@update_limit", SqlDbType.Int).Value =
            random.Next(1000, 5000);

        SqlParameter feeIncrementParameter =
            cmd.Parameters.Add("@fee_increment", SqlDbType.Decimal);

        feeIncrementParameter.Precision = 19;
        feeIncrementParameter.Scale = 2;
        feeIncrementParameter.Value = random.Next(10, 100);

        cmd.Parameters.Add("@status", SqlDbType.VarChar, 50).Value =
            Statuses[random.Next(Statuses.Length)];

        SqlParameter minimumAmountParameter =
            cmd.Parameters.Add("@minimum_amount", SqlDbType.Decimal);

        minimumAmountParameter.Precision = 19;
        minimumAmountParameter.Scale = 2;
        minimumAmountParameter.Value = random.Next(5000, 100000);

        return cmd;
    }

    private static SqlCommand BuildDeleteCommand(
        SqlConnection conn,
        SqlTransaction transaction,
        Random random
    )
    {
        string deleteSql =
        @"
        DELETE TOP (@delete_limit)
        FROM dbo.tbl_transactions_secure
        WHERE
            created_on < DATEADD(MINUTE, -@age_minutes, SYSUTCDATETIME())
            AND transaction_final_status = @status;
        ";

        SqlCommand cmd =
            new SqlCommand(
                deleteSql,
                conn,
                transaction,
                SqlCommandColumnEncryptionSetting.Enabled
            );

        cmd.Parameters.Add("@delete_limit", SqlDbType.Int).Value =
            random.Next(500, 3000);

        cmd.Parameters.Add("@age_minutes", SqlDbType.Int).Value =
            random.Next(1, 20);

        cmd.Parameters.Add("@status", SqlDbType.VarChar, 50).Value =
            Statuses[random.Next(Statuses.Length)];

        return cmd;
    }
}


// ## Recommended Starting Environment Variables

// ```bash
// export WORKER_COUNT=40
// export REPORTING_WORKERS=12
// export DEADLOCK_WORKERS=6
// export SESSION_HOLDER_COUNT=220
// export MAX_BATCHES=0
// export MIN_BATCH_SIZE=750
// export MAX_BATCH_SIZE=2500
// export BATCH_DELAY_MS=0
// export WORKLOAD_DURATION_MINUTES=30
// ```

// ## Expected Azure SQL Impact

// | Metric         | Expected Behavior       |
// | -------------- | ----------------------- |
// | DTU %          | sustained spikes        |
// | CPU %          | moderate/high           |
// | Log IO %       | heavy pressure          |
// | Data IO %      | fluctuating             |
// | Sessions %     | increased               |
// | Workers %      | increased               |
// | Deadlocks      | possible                |
// | Lock Waits     | likely                  |
// | Query Duration | unstable under pressure |

// ## Recommended Alert Rules

// | Metric              | Threshold |
// | ------------------- | --------- |
// | DTU Percentage      | > 80%     |
// | Log IO Percentage   | > 85%     |
// | CPU Percentage      | > 75%     |
// | Workers Percentage  | > 80%     |
// | Deadlocks           | > 0       |
// | Sessions Percentage | > 70%     |
