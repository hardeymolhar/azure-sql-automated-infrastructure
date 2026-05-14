#!/usr/bin/env bash

set -euo pipefail
source "$(dirname "$0")/env.conf"
# Configure Azure SQL auditing at both logical server and database level.
# Override these values when running the script if needed:
#   RESOURCE_GROUP="my-rg" SERVER_NAME="my-server" DB_NAME="my-db" ./sql-auditing.sh



SERVER_NAME=$(az sql server list \
  --resource-group "$RESOURCE_GROUP" \
  --query "[?contains(name, '$RESOURCE_SUFFIX')].name | [0]" \
  -o tsv)


if [[ -z "$RESOURCE_GROUP" ]]; then
  echo -e "${RED}No resource group found. Set RESOURCE_GROUP before running this script.${NC}"
  exit 1
fi

if [[ -z "$SERVER_NAME" ]]; then
  echo -e "${RED}No Azure SQL server found. Set SERVER_NAME before running this script.${NC}"
  exit 1
fi

echo -e "${GREEN}Resource group: $RESOURCE_GROUP${NC}"
echo -e "${GREEN}SQL server:     $SERVER_NAME${NC}"
echo -e "${GREEN}Database:       $DB_NAME${NC}"
echo -e "${GREEN}Workspace:      $LAW_NAME${NC}"


echo -e "${YELLOW}Configuring Azure SQL auditing...${NC}"
# Create the Log Analytics workspace if it does not already exist.
if ! az monitor log-analytics workspace show \
  --resource-group "$RESOURCE_GROUP" \
  --workspace-name "$LAW_NAME" \
  >/dev/null 2>&1; then

  az monitor log-analytics workspace create \
    --resource-group "$RESOURCE_GROUP" \
    --workspace-name "$LAW_NAME" \
    --location "$LOCATION"
fi


LAW_NAME="${LAW_NAME:-sql-audit-law}"
LAW_RESOURCE_ID=$(az monitor log-analytics workspace show \
  --resource-group "$RESOURCE_GROUP" \
  --workspace-name "$LAW_NAME" \
  --query id \
  -o tsv)

echo -e "${YELLOW} Updating audit policies...${NC}"
# Server-level auditing.
az sql server audit-policy update \
  --resource-group "$RESOURCE_GROUP" \
  --name "$SERVER_NAME" \
  --state Enabled \
  --log-analytics-target-state Enabled \
  --log-analytics-workspace-resource-id "$LAW_RESOURCE_ID" \
  --retention-days "$RETENTION_DAYS" \
  --actions \
  SUCCESSFUL_DATABASE_AUTHENTICATION_GROUP \
  FAILED_DATABASE_AUTHENTICATION_GROUP

# Database-level auditing.
az sql db audit-policy update \
  --resource-group "$RESOURCE_GROUP" \
  --server "$SERVER_NAME" \
  --name "$DB_NAME" \
  --state Enabled \
  --log-analytics-target-state Enabled \
  --log-analytics-workspace-resource-id "$LAW_RESOURCE_ID" \
  --retention-days "$RETENTION_DAYS" \
  --actions \
  SCHEMA_OBJECT_ACCESS_GROUP \
  DATABASE_OBJECT_CHANGE_GROUP \
  DATABASE_PERMISSION_CHANGE_GROUP


echo -e "${BLUE}Server audit policy:${NC}"
az sql server audit-policy show \
  --resource-group "$RESOURCE_GROUP" \
  --name "$SERVER_NAME" \
  -o table

echo -e "${BLUE}Database audit policy:${NC}"
az sql db audit-policy show \
  --resource-group "$RESOURCE_GROUP" \
  --server "$SERVER_NAME" \
  --name "$DB_NAME" \
  -o table

echo -e "${GREEN}Auditing configured successfully.${NC}"
