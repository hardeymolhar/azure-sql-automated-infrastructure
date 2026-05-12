
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
                : 6;

        int maxBatches =
            int.TryParse(
                Environment.GetEnvironmentVariable("MAX_BATCHES"),
                out int parsedMaxBatches
            )
                ? parsedMaxBatches
                : 25;

        int minBatchSize =
            int.TryParse(
                Environment.GetEnvironmentVariable("MIN_BATCH_SIZE"),
                out int parsedMinBatchSize
            )
                ? parsedMinBatchSize
                : 500;

        int maxBatchSize =
            int.TryParse(
                Environment.GetEnvironmentVariable("MAX_BATCH_SIZE"),
                out int parsedMaxBatchSize
            )
                ? parsedMaxBatchSize
                : 3000;

        int batchDelayMilliseconds =
            int.TryParse(
                Environment.GetEnvironmentVariable("BATCH_DELAY_MS"),
                out int parsedBatchDelayMilliseconds
            )
                ? parsedBatchDelayMilliseconds
                : 100;

        Console.WriteLine("================================================");
        Console.WriteLine("AZURE SQL CONCURRENT STRESS WORKLOAD");
        Console.WriteLine("================================================");
        Console.WriteLine($"Workers           : {workerCount}");
        Console.WriteLine($"Max Batches       : {maxBatches}");
        Console.WriteLine($"Min Batch Size    : {minBatchSize}");
        Console.WriteLine($"Max Batch Size    : {maxBatchSize}");
        Console.WriteLine($"Batch Delay (ms)  : {batchDelayMilliseconds}");
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
            $"Max Pool Size=200;" +
            $"Min Pool Size=20;" +
            $"MultipleActiveResultSets=False;";

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
                    batchDelayMilliseconds
                )
            );
        }

        tasks.Add(
            RunReportingWorker(
                connectionString,
                token.Token
            )
        );

        await Task.WhenAll(tasks);

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
        int batchDelayMilliseconds
    )
    {
        Random random =
            new Random(Guid.NewGuid().GetHashCode());

        for (int batchNumber = 1; batchNumber <= maxBatches; batchNumber++)
        {
            using SqlConnection conn =
                new SqlConnection(connectionString);

            conn.AccessToken = accessToken;

            await conn.OpenAsync();

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

                    await cmd.ExecuteNonQueryAsync();

                    Metrics.AddOrUpdate(
                        "Inserted Rows",
                        1,
                        (_, existing) => existing + 1
                    );

                    if (row % 250 == 0)
                    {
                        await Task.Delay(
                            random.Next(5, 25)
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
                    await updateCmd.ExecuteNonQueryAsync();

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
                    await deleteCmd.ExecuteNonQueryAsync();

                Metrics.AddOrUpdate(
                    "Deleted Rows",
                    deletedRows,
                    (_, existing) => existing + deletedRows
                );

                Console.WriteLine(
                    $"[Worker {workerId}] Deleted rows: {deletedRows}"
                );

                await Task.Delay(
                    random.Next(500, 3000)
                );

                await transaction.CommitAsync();

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
                    await transaction.RollbackAsync();
                }
                catch
                {
                }
            }

            if (batchDelayMilliseconds > 0)
            {
                await Task.Delay(batchDelayMilliseconds);
            }
        }
    }

    private static async Task RunReportingWorker(
        string connectionString,
        string accessToken
    )
    {
        while (true)
        {
            try
            {
                using SqlConnection conn =
                    new SqlConnection(connectionString);

                conn.AccessToken = accessToken;

                await conn.OpenAsync();

                string reportingSql =
                @"
                SELECT TOP (20)
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

                using SqlDataReader reader =
                    await reportCmd.ExecuteReaderAsync();

                int rows = 0;

                while (await reader.ReadAsync())
                {
                    rows++;
                }

                Console.WriteLine(
                    $"[REPORTING] Completed reporting query with {rows} result rows"
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

            await Task.Delay(2000);
        }
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
            new SqlCommand(insertSql, conn, transaction);

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

        cmd.Parameters.AddWithValue("@transaction_sub_type", transactionType);
        cmd.Parameters.AddWithValue("@transaction_type", transactionType);
        cmd.Parameters.AddWithValue("@amount", amount);
        cmd.Parameters.AddWithValue("@charged_fee", fee);
        cmd.Parameters.AddWithValue("@currency_code", "NGN");
        cmd.Parameters.AddWithValue("@source_account_number", random.NextInt64(1000000000, 9999999999).ToString());
        cmd.Parameters.AddWithValue("@destination_account_number", random.NextInt64(1000000000, 9999999999).ToString());
        cmd.Parameters.AddWithValue("@destination_account_name", "John Doe");
        cmd.Parameters.AddWithValue("@destination_bank_code", "044");
        cmd.Parameters.AddWithValue("@destination_bank_name", "Access Bank");
        cmd.Parameters.AddWithValue("@transaction_reference", Guid.NewGuid().ToString());
        cmd.Parameters.AddWithValue("@transaction_external_reference", Guid.NewGuid().ToString());
        cmd.Parameters.AddWithValue("@transaction_posting_reference", Guid.NewGuid().ToString());
        cmd.Parameters.AddWithValue("@request_transaction_id", Guid.NewGuid().ToString());
        cmd.Parameters.AddWithValue("@transaction_final_status", Statuses[random.Next(Statuses.Length)]);
        cmd.Parameters.AddWithValue("@transaction_request_status", Statuses[random.Next(Statuses.Length)]);
        cmd.Parameters.AddWithValue("@session_key", Guid.NewGuid().ToString());
        cmd.Parameters.AddWithValue("@recharge_pin", random.Next(1000, 9999).ToString());
        cmd.Parameters.AddWithValue("@electricity_token", random.NextInt64(100000000000, 999999999999).ToString());
        cmd.Parameters.AddWithValue("@user_name", Users[random.Next(Users.Length)]);
        cmd.Parameters.AddWithValue("@created_by", "concurrency-worker");
        cmd.Parameters.AddWithValue("@modified_by", "concurrency-worker");
        cmd.Parameters.AddWithValue("@created_on", now);
        cmd.Parameters.AddWithValue("@modified_on", now);
        cmd.Parameters.AddWithValue("@transaction_request_date", now);
        cmd.Parameters.AddWithValue("@transaction_response_date", now);
        cmd.Parameters.AddWithValue("@reversed", false);
        cmd.Parameters.AddWithValue("@vat_inclusive", true);

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
            new SqlCommand(updateSql, conn, transaction);

        cmd.Parameters.AddWithValue(
            "@update_limit",
            random.Next(1000, 5000)
        );

        cmd.Parameters.AddWithValue(
            "@fee_increment",
            random.Next(10, 100)
        );

        cmd.Parameters.AddWithValue(
            "@status",
            Statuses[random.Next(Statuses.Length)]
        );

        cmd.Parameters.AddWithValue(
            "@minimum_amount",
            random.Next(5000, 100000)
        );

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
            new SqlCommand(deleteSql, conn, transaction);

        cmd.Parameters.AddWithValue(
            "@delete_limit",
            random.Next(500, 3000)
        );

        cmd.Parameters.AddWithValue(
            "@age_minutes",
            random.Next(1, 20)
        );

        cmd.Parameters.AddWithValue(
            "@status",
            Statuses[random.Next(Statuses.Length)]
        );

        return cmd;
    }
}


// ## Recommended Starting Environment Variables

// ```bash
// export WORKER_COUNT=6
// export MAX_BATCHES=25
// export MIN_BATCH_SIZE=500
// export MAX_BATCH_SIZE=3000
// export BATCH_DELAY_MS=100
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
