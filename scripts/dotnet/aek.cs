using System;
using System.Threading.Tasks;
using Microsoft.Data.SqlClient;
using Azure.Identity;
using Azure.Core;

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