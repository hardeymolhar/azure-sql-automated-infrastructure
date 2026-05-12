#!/bin/bash
set -euo pipefail


RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color



RESOURCE_GROUP="$(az group list --query '[1].name' -o tsv)"

SERVER_NAME="$(az sql server list \
  --resource-group "$RESOURCE_GROUP" \
  --query "[?name != null && contains(name, '-99999990')].name | [0]" \
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

echo -e "${BLUE}Resource group: $RESOURCE_GROUP${NC}"
echo -e "${BLUE}SQL server:     $SERVER_NAME${NC}"
echo -e "${BLUE}Database:       $DB_NAME${NC}"

# =========================================================
# SHORT-TERM RETENTION (STR)
# =========================================================
echo -e "${YELLOW}Configuring STR policy...${NC}"

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

echo -e "${YELLOW}Configuring LTR policy...${NC}"

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

echo -e "${YELLOW}Verifying STR policy...${NC}"

az sql db str-policy show \
    --resource-group "$RESOURCE_GROUP" \
    --server "$SERVER_NAME" \
    --name "$DB_NAME" \
    -o table

# =========================================================
# VERIFY LTR
# =========================================================

echo -e "${YELLOW}Verifying LTR policy...${NC}"

az sql db ltr-policy show \
    --resource-group "$RESOURCE_GROUP" \
    --server "$SERVER_NAME" \
    --name "$DB_NAME" \
    -o table
