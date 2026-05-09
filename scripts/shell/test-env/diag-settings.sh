#!/bin/bash

set -euo pipefail

# ==========================================
# Azure SQL DB Monitoring Bootstrap
# Idempotent Version
# ==========================================

# ========= VARIABLES =========

RESOURCE_GROUP=$(az group list --query "[1].name" -o tsv)

LOCATION=$(az group show \
  --name "$RESOURCE_GROUP" \
  --query "location" \
  -o tsv)

SQL_SERVER_NAME=$(az sql server list \
  --resource-group "$RESOURCE_GROUP" \
  --query "[0].name" \
  -o tsv)

DATABASE_NAME="demo-db"

LOG_ANALYTICS_RG="$RESOURCE_GROUP"
LOG_ANALYTICS_NAME="sql-audit-law"

DIAG_SETTING_NAME="sql-db-diagnostics"

# ==========================================
# VALIDATION
# ==========================================

echo "Validating Azure SQL Database existence..."

if ! az sql db show \
    --resource-group "$RESOURCE_GROUP" \
    --server "$SQL_SERVER_NAME" \
    --name "$DATABASE_NAME" \
    >/dev/null 2>&1; then

    echo "ERROR: Database '$DATABASE_NAME' does not exist."
    exit 1
fi

echo "Database exists."

# ==========================================
# GET RESOURCE IDS
# ==========================================

SQL_DB_ID=$(az sql db show \
  --resource-group "$RESOURCE_GROUP" \
  --server "$SQL_SERVER_NAME" \
  --name "$DATABASE_NAME" \
  --query id \
  --output tsv)

# ==========================================
# CREATE LOG ANALYTICS WORKSPACE IF NEEDED
# ==========================================

echo "Checking Log Analytics Workspace..."

if az monitor log-analytics workspace show \
    --resource-group "$LOG_ANALYTICS_RG" \
    --workspace-name "$LOG_ANALYTICS_NAME" \
    >/dev/null 2>&1; then

    echo "Log Analytics Workspace already exists."

else

    echo "Creating Log Analytics Workspace..."

    az monitor log-analytics workspace create \
      --resource-group "$LOG_ANALYTICS_RG" \
      --workspace-name "$LOG_ANALYTICS_NAME" \
      --location "$LOCATION"

fi

LAW_ID=$(az monitor log-analytics workspace show \
  --resource-group "$LOG_ANALYTICS_RG" \
  --workspace-name "$LOG_ANALYTICS_NAME" \
  --query id \
  --output tsv)

# ==========================================
# CREATE DIAGNOSTIC SETTINGS IF NEEDED
# ==========================================

echo "Checking diagnostic settings..."

EXISTING_DIAG=$(az monitor diagnostic-settings show \
  --resource "$SQL_DB_ID" \
  --name "$DIAG_SETTING_NAME" \
  --query "name" \
  -o tsv 2>/dev/null || true)

if [[ "$EXISTING_DIAG" == "$DIAG_SETTING_NAME" ]]; then

    echo "Diagnostic setting already exists. Skipping."

else

    echo "Creating diagnostic settings..."

    az monitor diagnostic-settings create \
      --name "$DIAG_SETTING_NAME" \
      --resource "$SQL_DB_ID" \
      --workspace "$LAW_ID" \
      --export-to-resource-specific true \
      --logs '[
        {
          "category": "Errors",
          "enabled": true
        },
        {
          "category": "Deadlocks",
          "enabled": true
        },
        {
          "category": "Timeouts",
          "enabled": true
        },
        {
          "category": "Blocks",
          "enabled": true
        },
        {
          "category": "DatabaseWaitStatistics",
          "enabled": true
        },
        {
          "category": "SQLInsights",
          "enabled": true
        },
        {
          "category": "AutomaticTuning",
          "enabled": true
        },
        {
          "category": "QueryStoreRuntimeStatistics",
          "enabled": true
        },
        {
          "category": "QueryStoreWaitStatistics",
          "enabled": true
        }
      ]' \
      --metrics '[
        {
          "category": "AllMetrics",
          "enabled": true
        }
      ]'

    echo "Diagnostic settings created."

fi

# ==========================================
# QUERY STORE CONFIGURATION
# ==========================================

echo "Checking Query Store state..."

QUERY_STORE_STATE=$(az sql db query-store show \
  --resource-group "$RESOURCE_GROUP" \
  --server "$SQL_SERVER_NAME" \
  --database "$DATABASE_NAME" \
  --query "actualState" \
  -o tsv)

if [[ "$QUERY_STORE_STATE" == "ReadWrite" ]]; then

    echo "Query Store already enabled."

else

    echo "Enabling Query Store..."

    az sql db query-store update \
      --resource-group "$RESOURCE_GROUP" \
      --server "$SQL_SERVER_NAME" \
      --database "$DATABASE_NAME" \
      --operation-mode ReadWrite \
      --max-storage-size 2048 \
      --cleanup-policy-stale-query-threshold 30 \
      --query-capture-mode Auto

    echo "Query Store enabled."

fi

# ==========================================
# COMPLETE
# ==========================================

echo "=========================================="
echo "Azure SQL monitoring configuration complete."
echo "=========================================="