#!/bin/bash

# =========================================================
# Azure SQL Database Migration Script
# Source: SQL Server (On-Premises)
# Target: Azure SQL Database
# Tool: Azure Database Migration Service (DMS)
# =========================================================



# =========================================================
# INSTALL DATA MIGRATION EXTENSION
# =========================================================

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
# MIGRATE DATABASE SCHEMA
# =========================================================

echo "Migrating database schema..."

az datamigration sql-server-schema \
    --action "MigrateSchema" \
    --src-sql-connection-str "Server=$SOURCE_SERVER;Initial Catalog=$SOURCE_DB;User ID=$SOURCE_USER;Password=$SOURCE_PASSWORD" \
    --tgt-sql-connection-str "Server=$TARGET_SERVER.database.windows.net;Initial Catalog=$TARGET_DB;User ID=$TARGET_USER;Password=$TARGET_PASSWORD"

# =========================================================
# START FULL DATABASE MIGRATION
# =========================================================

echo "Starting full database migration..."

az datamigration sql-db create \
    --resource-group "$RESOURCE_GROUP" \
    --sqldb-instance-name "$TARGET_SERVER" \
    --target-db-name "$TARGET_DB" \
    --source-database-name "$SOURCE_DB" \
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
# OPTIONAL: MIGRATE SPECIFIC TABLES ONLY
# =========================================================
# Uncomment this section if you want partial migration

# echo "Migrating selected tables..."

# az datamigration sql-db create \
#     --resource-group "$RESOURCE_GROUP" \
#     --sqldb-instance-name "$TARGET_SERVER" \
#     --target-db-name "$TARGET_DB" \
#     --source-database-name "$SOURCE_DB" \
#     --source-sql-connection \
#         authentication="SqlAuthentication" \
#         data-source="$SOURCE_SERVER" \
#         user-name="$SOURCE_USER" \
#         password="$SOURCE_PASSWORD" \
#         encrypt-connection=true \
#         trust-server-certificate=true \
#     --target-sql-connection \
#         authentication="SqlAuthentication" \
#         data-source="$TARGET_SERVER.database.windows.net" \
#         user-name="$TARGET_USER" \
#         password="$TARGET_PASSWORD" \
#         encrypt-connection=true \
#         trust-server-certificate=true \
#     --table-list \
#         "[Person].[Person]" \
#         "[Person].[EmailAddress]" \
#         "[Sales].[Customer]" \
#     --scope "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.Sql/servers/$TARGET_SERVER" \
#     --migration-service "/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.DataMigration/sqlMigrationServices/$MIGRATION_SERVICE"

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
# WAIT FOR MIGRATION COMPLETION
# =========================================================

echo "Waiting for migration completion..."

az datamigration sql-db wait \
    --resource-group "$RESOURCE_GROUP" \
    --sqldb-instance-name "$TARGET_SERVER" \
    --target-db-name "$TARGET_DB" \
    --created

# =========================================================
# OPTIONAL: CANCEL MIGRATION
# =========================================================
# Uncomment if needed

# MIGRATION_OPERATION_ID="YourMigrationOperationId"

# echo "Cancelling migration..."

# az datamigration sql-db cancel \
#     --resource-group "$RESOURCE_GROUP" \
#     --sqldb-instance-name "$TARGET_SERVER" \
#     --target-db-name "$TARGET_DB" \
#     --migration-operation-id "$MIGRATION_OPERATION_ID"

# =========================================================
# END
# =========================================================

echo "Migration script execution completed."



az datamigration sql-service create \
    --resource-group "<RESOURCE_GROUP>" \
    --sql-migration-service-name "testdms001" \
    --location "eastus"