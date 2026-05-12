using System;
using System.Collections.Generic;
using System.Threading.Tasks;

using Azure.Core;
using Azure.Identity;

using Microsoft.Data.SqlClient;
using Microsoft.Data.SqlClient.AlwaysEncrypted.AzureKeyVaultProvider;

class Program
{
    static async Task Main()
    {
        string server =
            $"{Environment.GetEnvironmentVariable("SQL_SERVER_NAME")}.database.windows.net";

        string database =
            Environment.GetEnvironmentVariable("DATABASE_NAME")
            ?? throw new Exception(
                "DATABASE_NAME environment variable is missing."
            );

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
            $"Column Encryption Setting=Enabled;";

        using SqlConnection conn =
            new SqlConnection(connectionString);

        conn.AccessToken = token.Token;

        conn.FireInfoMessageEventOnUserErrors = true;

        conn.InfoMessage += (s, e) =>
        {
            Console.WriteLine(
                $"SQL INFO: {e.Message}"
            );
        };

        await conn.OpenAsync();

        Console.WriteLine(
            "Connected successfully."
        );

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

        string updateSql =
@"
UPDATE TOP (2000) dbo.tbl_transactions_secure
SET
    charged_fee = charged_fee + 25,
    modified_on = SYSUTCDATETIME(),
    modified_by = 'batch-update'
WHERE
    transaction_final_status = 'PENDING'
    AND reversed = 0;
";

        string deleteSql =
@"
DELETE TOP (1000)
FROM dbo.tbl_transactions_secure
WHERE
    reversed = 0
    AND created_on < DATEADD(MINUTE, -2, SYSUTCDATETIME());
";

        Random random = new Random();

        string[] transactionTypes =
        {
            "TRANSFER",
            "AIRTIME",
            "BILL_PAYMENT",
            "POS",
            "REVERSAL"
        };

        string[] statuses =
        {
            "SUCCESS",
            "PENDING",
            "FAILED"
        };

        string[] users =
        {
            "emmanuel",
            "daniel",
            "grace",
            "victor",
            "mary"
        };

        const int BatchSize = 2000;

        long totalInserted = 0;

        int maxBatches =
            int.TryParse(
                Environment.GetEnvironmentVariable(
                    "MAX_BATCHES"
                ),
                out int parsedMaxBatches
            )
                ? parsedMaxBatches
                : 5;

        int batchDelayMilliseconds =
            int.TryParse(
                Environment.GetEnvironmentVariable(
                    "BATCH_DELAY_MS"
                ),
                out int parsedBatchDelayMilliseconds
            )
                ? parsedBatchDelayMilliseconds
                : 250;

        for (
            int batchNumber = 1;
            batchNumber <= maxBatches;
            batchNumber++
        )
        {
            using SqlTransaction transaction =
                (SqlTransaction)
                    await conn.BeginTransactionAsync();

            long batchStart =
                totalInserted + 1;

            try
            {
                for (
                    int rowInBatch = 0;
                    rowInBatch < BatchSize;
                    rowInBatch++
                )
                {
                    using SqlCommand cmd =
                        new SqlCommand(
                            insertSql,
                            conn,
                            transaction
                        );

                    DateTime now =
                        DateTime.UtcNow;

                    string transactionType =
                        transactionTypes[
                            random.Next(
                                transactionTypes.Length
                            )
                        ];

                    decimal amount =
                        Math.Round(
                            (decimal)(
                                random.NextDouble() * 500000
                            ),
                            2
                        );

                    decimal fee =
                        Math.Round(
                            amount * 0.005m,
                            2
                        );

                    cmd.Parameters.Add(
                        new SqlParameter(
                            "@transaction_sub_type",
                            System.Data.SqlDbType.NVarChar,
                            31
                        )
                        {
                            Value = transactionType
                        });

                    cmd.Parameters.Add(
                        new SqlParameter(
                            "@transaction_type",
                            System.Data.SqlDbType.NVarChar,
                            50
                        )
                        {
                            Value = transactionType
                        });

                    cmd.Parameters.Add(
                        new SqlParameter(
                            "@amount",
                            System.Data.SqlDbType.Decimal
                        )
                        {
                            Precision = 19,
                            Scale = 2,
                            Value = amount
                        });

                    cmd.Parameters.Add(
                        new SqlParameter(
                            "@charged_fee",
                            System.Data.SqlDbType.Decimal
                        )
                        {
                            Precision = 19,
                            Scale = 2,
                            Value = fee
                        });

                    cmd.Parameters.Add(
                        new SqlParameter(
                            "@currency_code",
                            System.Data.SqlDbType.Char,
                            3
                        )
                        {
                            Value = "NGN"
                        });

                    cmd.Parameters.Add(
                        new SqlParameter(
                            "@source_account_number",
                            System.Data.SqlDbType.NVarChar,
                            20
                        )
                        {
                            Value = random.NextInt64(
                                1000000000,
                                9999999999
                            ).ToString()
                        });

                    cmd.Parameters.Add(
                        new SqlParameter(
                            "@destination_account_number",
                            System.Data.SqlDbType.NVarChar,
                            20
                        )
                        {
                            Value = random.NextInt64(
                                1000000000,
                                9999999999
                            ).ToString()
                        });

                    cmd.Parameters.Add(
                        new SqlParameter(
                            "@destination_account_name",
                            System.Data.SqlDbType.NVarChar,
                            150
                        )
                        {
                            Value = "John Doe"
                        });

                    cmd.Parameters.Add(
                        new SqlParameter(
                            "@destination_bank_code",
                            System.Data.SqlDbType.VarChar,
                            10
                        )
                        {
                            Value = "044"
                        });

                    cmd.Parameters.Add(
                        new SqlParameter(
                            "@destination_bank_name",
                            System.Data.SqlDbType.NVarChar,
                            100
                        )
                        {
                            Value = "Access Bank"
                        });

                    cmd.Parameters.Add(
                        new SqlParameter(
                            "@transaction_reference",
                            System.Data.SqlDbType.VarChar,
                            100
                        )
                        {
                            Value = Guid.NewGuid().ToString()
                        });

                    cmd.Parameters.Add(
                        new SqlParameter(
                            "@transaction_external_reference",
                            System.Data.SqlDbType.VarChar,
                            100
                        )
                        {
                            Value = Guid.NewGuid().ToString()
                        });

                    cmd.Parameters.Add(
                        new SqlParameter(
                            "@transaction_posting_reference",
                            System.Data.SqlDbType.VarChar,
                            100
                        )
                        {
                            Value = Guid.NewGuid().ToString()
                        });

                    cmd.Parameters.Add(
                        new SqlParameter(
                            "@request_transaction_id",
                            System.Data.SqlDbType.VarChar,
                            100
                        )
                        {
                            Value = Guid.NewGuid().ToString()
                        });

                    cmd.Parameters.Add(
                        new SqlParameter(
                            "@transaction_final_status",
                            System.Data.SqlDbType.VarChar,
                            50
                        )
                        {
                            Value = statuses[
                                random.Next(
                                    statuses.Length
                                )
                            ]
                        });

                    cmd.Parameters.Add(
                        new SqlParameter(
                            "@transaction_request_status",
                            System.Data.SqlDbType.VarChar,
                            50
                        )
                        {
                            Value = statuses[
                                random.Next(
                                    statuses.Length
                                )
                            ]
                        });

                    cmd.Parameters.Add(
                        new SqlParameter(
                            "@session_key",
                            System.Data.SqlDbType.NVarChar,
                            255
                        )
                        {
                            Value = Guid.NewGuid().ToString()
                        });

                    cmd.Parameters.Add(
                        new SqlParameter(
                            "@recharge_pin",
                            System.Data.SqlDbType.NVarChar,
                            50
                        )
                        {
                            Value = random.Next(
                                1000,
                                9999
                            ).ToString()
                        });

                    cmd.Parameters.Add(
                        new SqlParameter(
                            "@electricity_token",
                            System.Data.SqlDbType.NVarChar,
                            100
                        )
                        {
                            Value = random.NextInt64(
                                100000000000,
                                999999999999
                            ).ToString()
                        });

                    cmd.Parameters.Add(
                        new SqlParameter(
                            "@user_name",
                            System.Data.SqlDbType.NVarChar,
                            50
                        )
                        {
                            Value = users[
                                random.Next(
                                    users.Length
                                )
                            ]
                        });

                    cmd.Parameters.Add(
                        new SqlParameter(
                            "@created_by",
                            System.Data.SqlDbType.NVarChar,
                            100
                        )
                        {
                            Value = "batch-loader"
                        });

                    cmd.Parameters.Add(
                        new SqlParameter(
                            "@modified_by",
                            System.Data.SqlDbType.NVarChar,
                            100
                        )
                        {
                            Value = "batch-loader"
                        });

                    cmd.Parameters.Add(
                        new SqlParameter(
                            "@created_on",
                            System.Data.SqlDbType.DateTime2
                        )
                        {
                            Value = now
                        });

                    cmd.Parameters.Add(
                        new SqlParameter(
                            "@modified_on",
                            System.Data.SqlDbType.DateTime2
                        )
                        {
                            Value = now
                        });

                    cmd.Parameters.Add(
                        new SqlParameter(
                            "@transaction_request_date",
                            System.Data.SqlDbType.DateTime2
                        )
                        {
                            Value = now
                        });

                    cmd.Parameters.Add(
                        new SqlParameter(
                            "@transaction_response_date",
                            System.Data.SqlDbType.DateTime2
                        )
                        {
                            Value = now
                        });

                    cmd.Parameters.Add(
                        new SqlParameter(
                            "@reversed",
                            System.Data.SqlDbType.Bit
                        )
                        {
                            Value = false
                        });

                    cmd.Parameters.Add(
                        new SqlParameter(
                            "@vat_inclusive",
                            System.Data.SqlDbType.Bit
                        )
                        {
                            Value = true
                        });

                    await cmd.ExecuteNonQueryAsync();

                    totalInserted++;
                }

                await transaction.CommitAsync();

                Console.WriteLine(
                    $"Committed batch {batchNumber}/{maxBatches} " +
                    $"of {BatchSize} rows. " +
                    $"Rows {batchStart}-{totalInserted}. " +
                    $"Commit Time: {DateTime.UtcNow}"
                );

                using SqlCommand updateCmd =
                    new SqlCommand(updateSql, conn);

                int updatedRows =
                    await updateCmd.ExecuteNonQueryAsync();

                Console.WriteLine(
                    $"Updated rows: {updatedRows}"
                );

                using SqlCommand deleteCmd =
                    new SqlCommand(deleteSql, conn);

                int deletedRows =
                    await deleteCmd.ExecuteNonQueryAsync();

                Console.WriteLine(
                    $"Deleted rows: {deletedRows}"
                );

                Console.Out.Flush();

                if (batchDelayMilliseconds > 0)
                {
                    await Task.Delay(
                        batchDelayMilliseconds
                    );
                }
            }
            catch (Exception ex)
            {
                Console.WriteLine(
                    $"Transaction failed: {ex.Message}"
                );

                await transaction.RollbackAsync();

                throw;
            }
        }

        Console.WriteLine(
            $"Workload completed. Total inserted rows: {totalInserted}"
        );
    }
}