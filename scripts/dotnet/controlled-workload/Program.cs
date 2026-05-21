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

    private static readonly ConcurrentDictionary<string, long> Metrics =
        new();

    private static readonly DefaultAzureCredential Credential =
        new();

    static async Task Main()
    {
        string sqlServerName =
            Environment.GetEnvironmentVariable("SQL_SERVER_NAME")
            ?? throw new InvalidOperationException(
                "SQL_SERVER_NAME environment variable is required."
            );

        string databaseName =
            Environment.GetEnvironmentVariable("DATABASE_NAME")
            ?? throw new InvalidOperationException(
                "DATABASE_NAME environment variable is required."
            );

        int workerCount =
            ParseEnvironmentVariable("WORKER_COUNT", 2);

        int insertBatchSize =
            ParseEnvironmentVariable("INSERT_BATCH_SIZE", 8);

        int maxCycles =
            ParseEnvironmentVariable("MAX_CYCLES", 0);

        int workloadDurationMinutes =
            ParseEnvironmentVariable("WORKLOAD_DURATION_MINUTES", 0);

        int afterCommitDelayMilliseconds =
            ParseEnvironmentVariable("AFTER_COMMIT_DELAY_MS", 3000);

        int afterSelectDelayMilliseconds =
            ParseEnvironmentVariable("AFTER_SELECT_DELAY_MS", 5000);

        string connectionString =
            BuildConnectionString(sqlServerName, databaseName);

        RegisterAlwaysEncryptedProvider();

        Console.WriteLine("================================================");
        Console.WriteLine("AZURE SQL CONTROLLED 5 DTU WORKLOAD");
        Console.WriteLine("================================================");
        Console.WriteLine($"Workers                 : {workerCount}");
        Console.WriteLine($"Insert Batch Size       : {insertBatchSize}");
        Console.WriteLine(
            maxCycles > 0
                ? $"Max Cycles Per Worker   : {maxCycles}"
                : "Max Cycles Per Worker   : infinite"
        );
        Console.WriteLine(
            workloadDurationMinutes > 0
                ? $"Workload Duration (min) : {workloadDurationMinutes}"
                : "Workload Duration (min) : infinite"
        );
        Console.WriteLine($"After Commit Delay (ms) : {afterCommitDelayMilliseconds}");
        Console.WriteLine($"After Select Delay (ms) : {afterSelectDelayMilliseconds}");
        Console.WriteLine("================================================");

        using CancellationTokenSource cts =
            new();

        if (workloadDurationMinutes > 0)
        {
            cts.CancelAfter(
                TimeSpan.FromMinutes(
                    workloadDurationMinutes
                )
            );
        }

        List<Task> workers =
            new();

        for (int workerId = 1; workerId <= workerCount; workerId++)
        {
            int currentWorkerId =
                workerId;

            workers.Add(
                RunWorker(
                    currentWorkerId,
                    connectionString,
                    insertBatchSize,
                    maxCycles,
                    afterCommitDelayMilliseconds,
                    afterSelectDelayMilliseconds,
                    cts.Token
                )
            );
        }

        await Task.WhenAll(workers);

        Console.WriteLine("================================================");
        Console.WriteLine("CONTROLLED WORKLOAD COMPLETE");
        Console.WriteLine("================================================");

        foreach (var metric in Metrics)
        {
            Console.WriteLine($"{metric.Key}: {metric.Value}");
        }
    }

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
                    20,

                MinPoolSize =
                    0,

                ConnectTimeout =
                    30,

                MultipleActiveResultSets =
                    false,

                ColumnEncryptionSetting =
                    SqlConnectionColumnEncryptionSetting.Enabled
            };

        return builder.ConnectionString;
    }

    private static void RegisterAlwaysEncryptedProvider()
    {
        SqlColumnEncryptionAzureKeyVaultProvider provider =
            new(Credential);

        SqlConnection.RegisterColumnEncryptionKeyStoreProviders(
            new Dictionary<string, SqlColumnEncryptionKeyStoreProvider>
            {
                {
                    SqlColumnEncryptionAzureKeyVaultProvider.ProviderName,
                    provider
                }
            }
        );
    }

    private static async Task<SqlConnection> CreateConnection(
        string connectionString,
        CancellationToken cancellationToken
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
                ),
                cancellationToken
            );

        conn.AccessToken =
            token.Token;

        await conn.OpenAsync(cancellationToken);

        return conn;
    }

    private static async Task RunWorker(
        int workerId,
        string connectionString,
        int insertBatchSize,
        int maxCycles,
        int afterCommitDelayMilliseconds,
        int afterSelectDelayMilliseconds,
        CancellationToken cancellationToken
    )
    {
        Random random =
            new(Guid.NewGuid().GetHashCode());

        using SqlConnection conn =
            await CreateConnection(
                connectionString,
                cancellationToken
            );

        for (
            int cycle = 1;
            maxCycles <= 0 || cycle <= maxCycles;
            cycle++
        )
        {
            if (cancellationToken.IsCancellationRequested)
            {
                return;
            }

            await ExecuteWithRetry(
                async () =>
                {
                    int insertedRows =
                        await InsertSmallBatch(
                            conn,
                            workerId,
                            cycle,
                            insertBatchSize,
                            random,
                            cancellationToken
                        );

                    Metrics.AddOrUpdate(
                        "Inserted Rows",
                        insertedRows,
                        (_, value) => value + insertedRows
                    );
                },
                cancellationToken
            );

            await Delay(
                afterCommitDelayMilliseconds,
                cancellationToken
            );

            await ExecuteWithRetry(
                async () =>
                {
                    int resultRows =
                        await RunLightweightAggregate(
                            conn,
                            cancellationToken
                        );

                    Metrics.AddOrUpdate(
                        "Aggregate Queries",
                        1,
                        (_, value) => value + 1
                    );

                    Metrics.AddOrUpdate(
                        "Aggregate Result Rows",
                        resultRows,
                        (_, value) => value + resultRows
                    );
                },
                cancellationToken
            );

            await Delay(
                afterSelectDelayMilliseconds,
                cancellationToken
            );

            Console.WriteLine(
                    maxCycles > 0
                        ? $"[Worker {workerId}] Cycle {cycle}/{maxCycles} complete."
                        : $"[Worker {workerId}] Cycle {cycle} complete."
            );
        }
    }

    private static async Task<int> InsertSmallBatch(
        SqlConnection conn,
        int workerId,
        int cycle,
        int insertBatchSize,
        Random random,
        CancellationToken cancellationToken
    )
    {
        using SqlTransaction transaction =
            (SqlTransaction)await conn.BeginTransactionAsync(
                IsolationLevel.ReadCommitted,
                cancellationToken
            );

        try
        {
            for (int row = 0; row < insertBatchSize; row++)
            {
                using SqlCommand cmd =
                    BuildInsertCommand(
                        conn,
                        transaction,
                        random
                    );

                cmd.CommandTimeout =
                    30;

                await cmd.ExecuteNonQueryAsync(cancellationToken);
            }

            await transaction.CommitAsync(cancellationToken);

            Console.WriteLine(
                $"[Worker {workerId}] Committed cycle {cycle} " +
                $"with {insertBatchSize} rows."
            );

            return insertBatchSize;
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
        );
        ";

        SqlCommand cmd =
            new(
                insertSql,
                conn,
                transaction,
                SqlCommandColumnEncryptionSetting.Enabled
            );

        DateTime now =
            DateTime.UtcNow;

        string transactionType =
            TransactionTypes[
                random.Next(TransactionTypes.Length)
            ];

        decimal amount =
            Math.Round(
                (decimal)(random.NextDouble() * 50000),
                2
            );

        decimal fee =
            Math.Round(amount * 0.0025m, 2);

        cmd.Parameters.Add("@transaction_sub_type", SqlDbType.NVarChar, 31).Value =
            transactionType;

        cmd.Parameters.Add("@transaction_type", SqlDbType.NVarChar, 50).Value =
            transactionType;

        AddDecimalParameter(cmd, "@amount", amount);
        AddDecimalParameter(cmd, "@charged_fee", fee);

        cmd.Parameters.Add("@currency_code", SqlDbType.Char, 3).Value =
            "NGN";

        AddEncryptedNVarCharParameter(
            cmd,
            "@source_account_number",
            20,
            random.NextInt64(1000000000, 9999999999).ToString()
        );

        AddEncryptedNVarCharParameter(
            cmd,
            "@destination_account_number",
            20,
            random.NextInt64(1000000000, 9999999999).ToString()
        );

        AddEncryptedNVarCharParameter(
            cmd,
            "@destination_account_name",
            150,
            "John Doe"
        );

        cmd.Parameters.Add("@destination_bank_code", SqlDbType.VarChar, 10).Value =
            "044";

        cmd.Parameters.Add("@destination_bank_name", SqlDbType.NVarChar, 100).Value =
            "Access Bank";

        cmd.Parameters.Add("@transaction_reference", SqlDbType.VarChar, 100).Value =
            Guid.NewGuid().ToString();

        cmd.Parameters.Add("@transaction_external_reference", SqlDbType.VarChar, 100).Value =
            Guid.NewGuid().ToString();

        cmd.Parameters.Add("@transaction_posting_reference", SqlDbType.VarChar, 100).Value =
            Guid.NewGuid().ToString();

        cmd.Parameters.Add("@request_transaction_id", SqlDbType.VarChar, 100).Value =
            Guid.NewGuid().ToString();

        cmd.Parameters.Add("@transaction_final_status", SqlDbType.VarChar, 50).Value =
            Statuses[random.Next(Statuses.Length)];

        cmd.Parameters.Add("@transaction_request_status", SqlDbType.VarChar, 50).Value =
            Statuses[random.Next(Statuses.Length)];

        AddEncryptedNVarCharParameter(
            cmd,
            "@session_key",
            255,
            Guid.NewGuid().ToString()
        );

        AddEncryptedNVarCharParameter(
            cmd,
            "@recharge_pin",
            50,
            random.Next(1000, 9999).ToString()
        );

        AddEncryptedNVarCharParameter(
            cmd,
            "@electricity_token",
            100,
            random.NextInt64(100000000000, 999999999999).ToString()
        );

        cmd.Parameters.Add("@user_name", SqlDbType.NVarChar, 50).Value =
            Users[random.Next(Users.Length)];

        cmd.Parameters.Add("@created_by", SqlDbType.NVarChar, 100).Value =
            "controlled-workload";

        cmd.Parameters.Add("@modified_by", SqlDbType.NVarChar, 100).Value =
            "controlled-workload";

        cmd.Parameters.Add("@created_on", SqlDbType.DateTime2).Value =
            now;

        cmd.Parameters.Add("@modified_on", SqlDbType.DateTime2).Value =
            now;

        cmd.Parameters.Add("@transaction_request_date", SqlDbType.DateTime2).Value =
            now;

        cmd.Parameters.Add("@transaction_response_date", SqlDbType.DateTime2).Value =
            now;

        cmd.Parameters.Add("@reversed", SqlDbType.Bit).Value =
            false;

        cmd.Parameters.Add("@vat_inclusive", SqlDbType.Bit).Value =
            true;

        return cmd;
    }

    private static async Task<int> RunLightweightAggregate(
        SqlConnection conn,
        CancellationToken cancellationToken
    )
    {
        string sql =
        @"
        SELECT TOP (10)
            transaction_type,
            transaction_final_status,
            COUNT_BIG(*) AS total_transactions,
            SUM(amount) AS total_amount,
            AVG(amount) AS average_amount
        FROM dbo.tbl_transactions_secure
        WHERE
            created_on >= DATEADD(MINUTE, -15, SYSUTCDATETIME())
            AND reversed = 0
        GROUP BY
            transaction_type,
            transaction_final_status
        ORDER BY
            total_transactions DESC;
        ";

        using SqlCommand cmd =
            new(sql, conn);

        cmd.CommandTimeout =
            30;

        using SqlDataReader reader =
            await cmd.ExecuteReaderAsync(cancellationToken);

        int rows =
            0;

        while (await reader.ReadAsync(cancellationToken))
        {
            rows++;
        }

        return rows;
    }

    private static void AddDecimalParameter(
        SqlCommand cmd,
        string name,
        decimal value
    )
    {
        SqlParameter parameter =
            cmd.Parameters.Add(name, SqlDbType.Decimal);

        parameter.Precision =
            19;

        parameter.Scale =
            2;

        parameter.Value =
            value;
    }

    private static void AddEncryptedNVarCharParameter(
        SqlCommand cmd,
        string name,
        int size,
        string value
    )
    {
        cmd.Parameters.Add(
            new SqlParameter(
                name,
                SqlDbType.NVarChar,
                size
            )
            {
                ForceColumnEncryption = true,
                Value = value
            });
    }

    private static async Task ExecuteWithRetry(
        Func<Task> operation,
        CancellationToken cancellationToken
    )
    {
        const int maxAttempts =
            5;

        for (int attempt = 1; attempt <= maxAttempts; attempt++)
        {
            try
            {
                await operation();
                return;
            }
            catch (SqlException ex)
                when (
                    RetryableErrors.Contains(ex.Number) &&
                    attempt < maxAttempts
                )
            {
                Metrics.AddOrUpdate(
                    "Retryable SQL Errors",
                    1,
                    (_, value) => value + 1
                );

                int delayMilliseconds =
                    Math.Min(15000, attempt * 2000);

                Console.WriteLine(
                    $"Retryable SQL error {ex.Number}; " +
                    $"attempt {attempt}/{maxAttempts}. " +
                    $"Waiting {delayMilliseconds} ms."
                );

                await Delay(
                    delayMilliseconds,
                    cancellationToken
                );
            }
        }
    }

    private static async Task Delay(
        int delayMilliseconds,
        CancellationToken cancellationToken
    )
    {
        if (delayMilliseconds > 0)
        {
            try
            {
                await Task.Delay(
                    delayMilliseconds,
                    cancellationToken
                );
            }
            catch (OperationCanceledException)
            {
            }
        }
    }

    private static int ParseEnvironmentVariable(
        string variableName,
        int defaultValue
    )
    {
        return int.TryParse(
            Environment.GetEnvironmentVariable(variableName),
            out int parsedValue
        )
            ? parsedValue
            : defaultValue;
    }
}
