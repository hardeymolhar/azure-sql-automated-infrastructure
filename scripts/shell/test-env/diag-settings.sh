#!/bin/bash

set -euo pipefail


RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

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

echo -e "${YELLOW}Validating Azure SQL Database existence...${NC}"

if ! az sql db show \
    --resource-group "$RESOURCE_GROUP" \
    --server "$SQL_SERVER_NAME" \
    --name "$DATABASE_NAME" \
    >/dev/null 2>&1; then

    echo -e "${RED}ERROR: Database '$DATABASE_NAME' does not exist.${NC}"
    exit 1
fi

echo -e "${GREEN}Database exists.${NC}"

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

echo -e "${YELLOW}Checking Log Analytics Workspace...${NC}"

if az monitor log-analytics workspace show \
    --resource-group "$LOG_ANALYTICS_RG" \
    --workspace-name "$LOG_ANALYTICS_NAME" \
    >/dev/null 2>&1; then

    echo -e "${GREEN}Log Analytics Workspace already exists.${NC} Skipping creation."

else

    echo -e "${YELLOW}Creating Log Analytics Workspace...${NC}"

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

echo -e "${YELLOW}Checking diagnostic settings...${NC}"

EXISTING_DIAG=$(az monitor diagnostic-settings show \
  --resource "$SQL_DB_ID" \
  --name "$DIAG_SETTING_NAME" \
  --query "name" \
  -o tsv 2>/dev/null || true)

if [[ "$EXISTING_DIAG" == "$DIAG_SETTING_NAME" ]]; then

    echo -e "${GREEN}Diagnostic setting already exists. Skipping.${NC}"

else

    echo -e "${YELLOW}Creating diagnostic settings...${NC}"

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

    echo -e "${GREEN}Diagnostic settings created.${NC}"

fi
