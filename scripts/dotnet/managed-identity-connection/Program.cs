using System;
using System.Threading.Tasks;

using Microsoft.Data.SqlClient;

using Azure.Core;
using Azure.Identity;

class Program
{
    static async Task Main()
    {
        string? sqlServerName =
            Environment.GetEnvironmentVariable(
                "SQL_SERVER_NAME"
            );

        string? databaseName =
            Environment.GetEnvironmentVariable(
                "DATABASE_NAME"
            );

        if (
            string.IsNullOrWhiteSpace(sqlServerName) ||
            string.IsNullOrWhiteSpace(databaseName)
        )
        {
            Console.WriteLine(
                "Missing required environment variables."
            );

            return;
        }

        string server =
            $"{sqlServerName}.database.windows.net";

        var credential =
            new DefaultAzureCredential();

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
            $"Database={databaseName};" +
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

        using SqlCommand cmd =
            new SqlCommand(
                "SELECT GETDATE()",
                conn
            );

        var result =
            await cmd.ExecuteScalarAsync();

        Console.WriteLine(
            $"Server Time: {result}"
        );
    }
}