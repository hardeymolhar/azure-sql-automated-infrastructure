#!/bin/bash

# =========================================================
# Azure SQL Database ONLINE Migration Script
# Source : SQL Server (On-Premises)
# Target : Azure SQL Database
# Tool   : Azure Database Migration Service (DMS)
# Mode   : ONLINE MIGRATION
# =========================================================

# =========================================================
# IMPORTANT
# =========================================================
# ONLINE migration requires:
# 1. Change Data Capture (CDC) enabled
# 2. Continuous synchronization
# 3. Final cutover step
#
# This script assumes:
# - Source SQL Server supports CDC
# - Azure SQL Database already exists
# - Firewall rules are configured
# - SQL Authentication is enabled
# =========================================================


# =========================================================
# INSTALL DMS EXTENSION
# =========================================================

echo "Installing Azure DMS extension..."

az extension add --name datamigration


# =========================================================
# CREATE AZURE DATABASE MIGRATION SERVICE
# =========================================================

echo "Creating Azure Database Migration Service..."

az datamigration sql-service create \
    --resource-group "$RESOURCE_GROUP" \
    --sql-migration-service-name "$MIGRATION_SERVICE" \
    --location "$LOCATION"


# =========================================================
# ENABLE CDC ON SOURCE DATABASE
# =========================================================
# Run these manually on the source SQL Server
#
# USE master;
# GO
# EXEC sys.sp_cdc_enable_db;
# GO
#
# USE AdventureWorks;
# GO
#
# EXEC sys.sp_cdc_enable_table
#     @source_schema = N'Person',
#     @source_name   = N'Person',
#     @role_name     = NULL,
#     @supports_net_changes = 1;
# GO
# =========================================================




# NOTE: ENSURE TO VALIDATE THE QUALITY OF THE GENERATED CODE AND TEST IT IN A SAFE ENVIRONMENT BEFORE USING IT IN PRODUCTION.
# =========================================================
# ENABLE CDC AT SCALE ON SOURCE DATABASE
# =========================================================
# USE AdventureWorks;
# GO

# DECLARE @sql NVARCHAR(MAX) = N'';

# SELECT @sql += '
# EXEC sys.sp_cdc_enable_table
#     @source_schema = N''' + s.name + ''',
#     @source_name   = N''' + t.name + ''',
#     @role_name     = NULL,
#     @supports_net_changes = 1;
# GO
# '
# FROM sys.tables t
# INNER JOIN sys.schemas s
#     ON t.schema_id = s.schema_id
# WHERE s.name IN ('Person', 'Sales', 'Production')
# AND t.is_ms_shipped = 0
# AND t.name NOT LIKE '%Archive%'
# AND t.name NOT LIKE '%Audit%'

# PRINT @sql;


# =========================================================
# MIGRATE DATABASE SCHEMA USING SQL AUTH
# =========================================================

echo "Migrating database schema..."

az datamigration sql-server-schema \
    --action "MigrateSchema" \
    --src-sql-connection-str \
        "Server=$SOURCE_SERVER;Initial Catalog=$SOURCE_DB;User ID=$SOURCE_USER;Password=$SOURCE_PASSWORD" \
    --tgt-sql-connection-str \
        "Server=$TARGET_SERVER.database.windows.net;Initial Catalog=$TARGET_DB;User ID=$TARGET_USER;Password=$TARGET_PASSWORD"


# =========================================================
# START ONLINE DATABASE MIGRATION
# =========================================================
# ONLINE mode performs:
# - Initial full load
# - Continuous CDC synchronization
# - Minimal downtime cutover
# =========================================================

echo "Starting ONLINE database migration..."

az datamigration sql-db create \
    --resource-group "$RESOURCE_GROUP" \
    --sqldb-instance-name "$TARGET_SERVER" \
    --target-db-name "$TARGET_DB" \
    --source-database-name "$SOURCE_DB" \
    --migration-mode "Online" \
    --source-sql-connection \
        authentication="SqlAuthentication" \
        data-source="$SOURCE_SERVER" \
        user-name="$SOURCE_USER" \
        password="$SOURCE_PASSWORD" \
        encrypt-connection=true \
        trust-server-certificate=true \
    --target-sql-connection \
        authentication="SqlAuthentication" \
        data-source="$TARGET_SERVER.database.windows.net" \
        user-name="$TARGET_USER" \
        password="$TARGET_PASSWORD" \
        encrypt-connection=true \
        trust-server-certificate=true \
    --scope "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.Sql/servers/$TARGET_SERVER" \
    --migration-service "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.DataMigration/sqlMigrationServices/$MIGRATION_SERVICE"


# =========================================================
# CHECK MIGRATION STATUS
# =========================================================

echo "Checking migration status..."

az datamigration sql-db show \
    --resource-group "$RESOURCE_GROUP" \
    --sqldb-instance-name "$TARGET_SERVER" \
    --target-db-name "$TARGET_DB" \
    --expand "MigrationStatusDetails"


# =========================================================
# WAIT FOR INITIAL LOAD COMPLETION
# =========================================================

echo "Waiting for initial synchronization..."

az datamigration sql-db wait \
    --resource-group "$RESOURCE_GROUP" \
    --sqldb-instance-name "$TARGET_SERVER" \
    --target-db-name "$TARGET_DB" \
    --created


# =========================================================
# CUTOVER PHASE
# =========================================================
# During cutover:
# 1. Stop application writes
# 2. Allow final synchronization
# 3. Redirect application connections
# =========================================================

echo "ONLINE migration initialized."
echo "Monitor synchronization status before final cutover."


# =========================================================
# OPTIONAL: CANCEL MIGRATION
# =========================================================

# MIGRATION_OPERATION_ID="YourMigrationOperationId"

# az datamigration sql-db cancel \
#     --resource-group "$RESOURCE_GROUP" \
#     --sqldb-instance-name "$TARGET_SERVER" \
#     --target-db-name "$TARGET_DB" \
#     --migration-operation-id "$MIGRATION_OPERATION_ID"


# =========================================================
# END
# =========================================================

echo "Online migration script execution completed."
