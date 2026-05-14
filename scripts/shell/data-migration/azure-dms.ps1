# =========================================================
# Azure SQL Database Migration using PowerShell
# Source: SQL Server (On-Premises)
# Target: Azure SQL Database
# =========================================================

# ---------------------------------------------------------
# VARIABLES
# ---------------------------------------------------------

$ResourceGroup     = "YourResourceGroup"
$SubscriptionId    = "YourSubscription"

$TargetServer      = "YourTargetServer"
$TargetDatabase    = "YourTargetDB"
$TargetUser        = "YourTargetUser"
$TargetPassword    = "YourTargetPassword"

$SourceServer      = "YourSourceServer"
$SourceDatabase    = "YourSourceDB"
$SourceUser        = "YourSourceUser"
$SourcePassword    = "YourSourcePassword"

$MigrationService  = "YourMigrationService"

# ---------------------------------------------------------
# CONVERT PASSWORDS TO SECURE STRINGS
# ---------------------------------------------------------

$SourcePass = ConvertTo-SecureString `
    $SourcePassword `
    -AsPlainText `
    -Force

$TargetPass = ConvertTo-SecureString `
    $TargetPassword `
    -AsPlainText `
    -Force

# ---------------------------------------------------------
# START FULL DATABASE MIGRATION
# ---------------------------------------------------------

Write-Host "Starting full database migration..." -ForegroundColor Cyan

New-AzDataMigrationToSqlDb `
    -ResourceGroupName $ResourceGroup `
    -SqlDbInstanceName $TargetServer `
    -Kind "SqlDb" `
    -TargetDbName $TargetDatabase `
    -SourceDatabaseName $SourceDatabase `
    -SourceSqlConnectionAuthentication SQLAuthentication `
    -SourceSqlConnectionDataSource $SourceServer `
    -SourceSqlConnectionUserName $SourceUser `
    -SourceSqlConnectionPassword $SourcePass `
    -Scope "/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroup/providers/Microsoft.Sql/servers/$TargetServer" `
    -TargetSqlConnectionAuthentication SQLAuthentication `
    -TargetSqlConnectionDataSource "$TargetServer.database.windows.net" `
    -TargetSqlConnectionUserName $TargetUser `
    -TargetSqlConnectionPassword $TargetPass `
    -MigrationService "/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroup/providers/Microsoft.DataMigration/SqlMigrationServices/$MigrationService"

# ---------------------------------------------------------
# OPTIONAL: MIGRATE SPECIFIC TABLES ONLY
# ---------------------------------------------------------
# Uncomment this section if you want partial migration

<#
Write-Host "Starting partial table migration..." -ForegroundColor Yellow

New-AzDataMigrationToSqlDb `
    -ResourceGroupName $ResourceGroup `
    -SqlDbInstanceName $TargetServer `
    -Kind "SqlDb" `
    -TargetDbName $TargetDatabase `
    -SourceDatabaseName $SourceDatabase `
    -SourceSqlConnectionAuthentication SQLAuthentication `
    -SourceSqlConnectionDataSource $SourceServer `
    -SourceSqlConnectionUserName $SourceUser `
    -SourceSqlConnectionPassword $SourcePass `
    -Scope "/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroup/providers/Microsoft.Sql/servers/$TargetServer" `
    -TargetSqlConnectionAuthentication SQLAuthentication `
    -TargetSqlConnectionDataSource "$TargetServer.database.windows.net" `
    -TargetSqlConnectionUserName $TargetUser `
    -TargetSqlConnectionPassword $TargetPass `
    -TableList `
        "[Person].[Person]", `
        "[Person].[EmailAddress]", `
        "[Sales].[Customer]" `
    -MigrationService "/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroup/providers/Microsoft.DataMigration/SqlMigrationServices/$MigrationService"
#>

# ---------------------------------------------------------
# END
# ---------------------------------------------------------

Write-Host "Migration command submitted successfully." -ForegroundColor Green