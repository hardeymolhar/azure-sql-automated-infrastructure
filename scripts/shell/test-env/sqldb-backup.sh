#!/bin/bash

set -euo pipefail

RESOURCE_GROUP="$(az group list --query '[1].name' -o tsv)"

SERVER_NAME="$(az sql server list \
  --resource-group "$RESOURCE_GROUP" \
  --query "[?name != null && contains(name, '-2348o1')].name | [0]" \
  -o tsv
)"

DB_NAME="demo-db"


if [[ -z "$RESOURCE_GROUP" ]]; then
    echo "ERROR: No resource group found. Set RESOURCE_GROUP before running this script."
    exit 1
fi

if [[ -z "$SERVER_NAME" ]]; then
    echo "ERROR: No Azure SQL server found. Set SERVER_NAME before running this script."
    exit 1
fi

if [[ -z "$DB_NAME" ]]; then
    echo "ERROR: No database name provided. Set DB_NAME before running this script."
    exit 1
fi

echo "Resource group: $RESOURCE_GROUP"
echo "SQL server:     $SERVER_NAME"
echo "Database:       $DB_NAME"

# =========================================================
# SHORT-TERM RETENTION (STR)
# =========================================================
echo "Configuring STR policy..."

az sql db str-policy set \
  --resource-group "$RESOURCE_GROUP" \
  --server "$SERVER_NAME" \
  --name "$DB_NAME" \
  --retention-days 7 \
  --diffbackup-hours 24

# =========================================================
# LONG-TERM RETENTION (LTR)
# =========================================================

WEEKLY_RETENTION="P12W"
MONTHLY_RETENTION="P12M"
YEARLY_RETENTION="P7Y"
WEEK_OF_YEAR=26

echo "Configuring LTR policy..."

az sql db ltr-policy set \
    --resource-group "$RESOURCE_GROUP" \
    --server "$SERVER_NAME" \
    --name "$DB_NAME" \
    --weekly-retention "$WEEKLY_RETENTION" \
    --monthly-retention "$MONTHLY_RETENTION" \
    --yearly-retention "$YEARLY_RETENTION" \
    --week-of-year "$WEEK_OF_YEAR"

# =========================================================
# VERIFY STR
# =========================================================

echo "Verifying STR policy..."

az sql db str-policy show \
    --resource-group "$RESOURCE_GROUP" \
    --server "$SERVER_NAME" \
    --name "$DB_NAME" \
    -o table

# =========================================================
# VERIFY LTR
# =========================================================

echo "Verifying LTR policy..."

az sql db ltr-policy show \
    --resource-group "$RESOURCE_GROUP" \
    --server "$SERVER_NAME" \
    --name "$DB_NAME" \
    -o table
