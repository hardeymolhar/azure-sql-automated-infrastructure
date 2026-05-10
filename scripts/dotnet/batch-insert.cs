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
            "sqlserver-2348o1.database.windows.net";

        string database =
            "demo-db";

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

        while (true)
        {
            using SqlCommand cmd =
                new SqlCommand(insertSql, conn);

            DateTime now = DateTime.UtcNow;

            decimal amount =
                Math.Round(
                    (decimal)(random.NextDouble() * 500000),
                    2
                );

            decimal fee =
                Math.Round(amount * 0.005m, 2);

            cmd.Parameters.Add(
                new SqlParameter(
                    "@transaction_sub_type",
                    System.Data.SqlDbType.NVarChar,
                    31
                )
                {
                    Value = "TRANSFER"
                });

            cmd.Parameters.Add(
                new SqlParameter(
                    "@transaction_type",
                    System.Data.SqlDbType.NVarChar,
                    50
                )
                {
                    Value = "TRANSFER"
                });

            cmd.Parameters.AddWithValue(
                "@amount",
                amount
            );

            cmd.Parameters.AddWithValue(
                "@charged_fee",
                fee
            );

            cmd.Parameters.AddWithValue(
                "@currency_code",
                "NGN"
            );

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

            cmd.Parameters.AddWithValue(
                "@destination_bank_code",
                "044"
            );

            cmd.Parameters.AddWithValue(
                "@destination_bank_name",
                "Access Bank"
            );

            cmd.Parameters.AddWithValue(
                "@transaction_reference",
                Guid.NewGuid().ToString()
            );

            cmd.Parameters.AddWithValue(
                "@transaction_external_reference",
                Guid.NewGuid().ToString()
            );

            cmd.Parameters.AddWithValue(
                "@transaction_posting_reference",
                Guid.NewGuid().ToString()
            );

            cmd.Parameters.AddWithValue(
                "@request_transaction_id",
                Guid.NewGuid().ToString()
            );

            cmd.Parameters.AddWithValue(
                "@transaction_final_status",
                statuses[random.Next(statuses.Length)]
            );

            cmd.Parameters.AddWithValue(
                "@transaction_request_status",
                statuses[random.Next(statuses.Length)]
            );

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
                    Value = random.Next(1000, 9999).ToString()
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

            cmd.Parameters.AddWithValue(
                "@user_name",
                users[random.Next(users.Length)]
            );

            cmd.Parameters.AddWithValue(
                "@created_by",
                "batch-loader"
            );

            cmd.Parameters.AddWithValue(
                "@modified_by",
                "batch-loader"
            );

            cmd.Parameters.AddWithValue(
                "@created_on",
                now
            );

            cmd.Parameters.AddWithValue(
                "@modified_on",
                now
            );

            cmd.Parameters.AddWithValue(
                "@transaction_request_date",
                now
            );

            cmd.Parameters.AddWithValue(
                "@transaction_response_date",
                now
            );

            cmd.Parameters.AddWithValue(
                "@reversed",
                false
            );

            cmd.Parameters.AddWithValue(
                "@vat_inclusive",
                true
            );

            await cmd.ExecuteNonQueryAsync();

            Console.WriteLine(
                $"Inserted row at {DateTime.UtcNow}"
            );

            await Task.Delay(1000);
        }
    }
}