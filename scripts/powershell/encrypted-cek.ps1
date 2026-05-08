# =========================================================
# STEP 1 — Discover SQL Server
# =========================================================

$sqlServerName = az sql server list `
    --query "[0].name" `
    -o tsv


# =========================================================
# STEP 2 — Discover Resource Group
# =========================================================

$resourceGroup = az sql server list `
    --query "[?name=='$sqlServerName'].resourceGroup | [0]" `
    -o tsv


# =========================================================
# STEP 3 — Retrieve SQL Server FQDN
# =========================================================

$serverName = az sql server show `
    --name $sqlServerName `
    --resource-group $resourceGroup `
    --query fullyQualifiedDomainName `
    -o tsv


# =========================================================
# STEP 4 — Discover User Database
# =========================================================

$databaseName = az sql db list `
    --resource-group $resourceGroup `
    --server $sqlServerName `
    --query "[?name!='master'].name | [0]" `
    -o tsv


# =========================================================
# STEP 5 — Acquire Azure SQL Access Token
# =========================================================

$token = az account get-access-token `
    --resource https://database.windows.net/ `
    --query accessToken `
    -o tsv


# =========================================================
# STEP 6 — Discover Key Vault
# =========================================================

$keyVaultName = az keyvault list `
    --resource-group $resourceGroup `
    --query "[0].name" `
    -o tsv


# =========================================================
# STEP 7 — Define Always Encrypted Objects
# =========================================================

$keyName = "always-encrypted-key"

$cmkName = "AE_CMK"

$cekName = "AE_CEK"


# =========================================================
# STEP 8 — Retrieve Key Vault CMK
# =========================================================

$key = Get-AzKeyVaultKey `
    -VaultName $keyVaultName `
    -Name $keyName

$keyPath = $key.Key.Kid


# =========================================================
# STEP 9 — Create CMK Settings Object
# =========================================================

$cmkSettings = New-SqlAzureKeyVaultColumnMasterKeySettings `
    -KeyUrl $keyPath


# =========================================================
# STEP 10 — Create SQL  Connection
# =========================================================

$sqlConnection = New-Object Microsoft.Data.SqlClient.SqlConnection

$sqlConnection.ConnectionString = @"

Server=tcp:$serverName,1433;

Database=$databaseName;

Encrypt=True;

TrustServerCertificate=False;

Column Encryption Setting=Enabled;

"@

$sqlConnection.AccessToken = $token

$sqlConnection.Open()

# =========================================================
# STEP 11 — Create SQL SMO Server Object
# =========================================================

$serverConnection = New-Object Microsoft.SqlServer.Management.Common.ServerConnection -ArgumentList $sqlConnection

$server = New-Object Microsoft.SqlServer.Management.Smo.Server -ArgumentList $serverConnection

# =========================================================
# STEP 12 — Retrieve SMO Database Object
# =========================================================

$database = $server.Databases[$databaseName]

if ($null -eq $database) {
    throw "Database '$databaseName' was not found on server '$serverName'."
}


# =========================================================
# STEP 13 — Create Column Master Key Metadata
# =========================================================

New-SqlColumnMasterKey `
    -Name $cmkName `
    -InputObject $database `
    -ColumnMasterKeySettings $cmkSettings


# =========================================================
# STEP 14 — Create Column Encryption Key
# =========================================================

New-SqlColumnEncryptionKey `
    -Name $cekName `
    -InputObject $database `
    -ColumnMasterKey $cmkName
