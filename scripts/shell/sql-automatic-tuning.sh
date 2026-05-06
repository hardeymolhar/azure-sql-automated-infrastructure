#!/usr/bin/env bash

set -euo pipefail

# Configure Azure SQL Database automatic tuning at database level.
# Microsoft docs note that active geo-replication should be configured on
# the primary database only; tuning actions replicate to geo-secondaries.
#
# Override values when running if needed:
#   RESOURCE_GROUP="my-rg" SERVER_NAME="my-server" DB_NAME="my-db" ./sql-automatic-tuning.sh

RESOURCE_GROUP="${RESOURCE_GROUP:-$(az group list --query "[0].name" -o tsv)}"
SERVER_NAME="${SERVER_NAME:-$(az sql server list --resource-group "$RESOURCE_GROUP" --query "[0].name" -o tsv)}"
DB_NAME="${DB_NAME:-demo-db}"
SUBSCRIPTION_ID="${SUBSCRIPTION_ID:-$(az account show --query id -o tsv)}"

# Database automatic tuning states: Auto, Inherit, Custom.
DESIRED_STATE="${DESIRED_STATE:-Custom}"

# Option states: On, Off, Default.
FORCE_LAST_GOOD_PLAN="${FORCE_LAST_GOOD_PLAN:-On}"
CREATE_INDEX="${CREATE_INDEX:-On}"
DROP_INDEX="${DROP_INDEX:-Off}"

API_VERSION="${API_VERSION:-2023-08-01}"

if [[ -z "$RESOURCE_GROUP" ]]; then
  echo "No resource group found. Set RESOURCE_GROUP before running this script."
  exit 1
fi

if [[ -z "$SERVER_NAME" ]]; then
  echo "No Azure SQL server found. Set SERVER_NAME before running this script."
  exit 1
fi

if [[ -z "$DB_NAME" ]]; then
  echo "No database name provided. Set DB_NAME before running this script."
  exit 1
fi

echo "Resource group:         $RESOURCE_GROUP"
echo "SQL server:             $SERVER_NAME"
echo "Database:               $DB_NAME"
echo "Desired tuning state:   $DESIRED_STATE"
echo "Force last good plan:   $FORCE_LAST_GOOD_PLAN"
echo "Create index:           $CREATE_INDEX"
echo "Drop index:             $DROP_INDEX"

URI="https://management.azure.com/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.Sql/servers/${SERVER_NAME}/databases/${DB_NAME}/automaticTuning/current?api-version=${API_VERSION}"

REQUEST_BODY=$(printf \
  '{"properties":{"desiredState":"%s","options":{"forceLastGoodPlan":{"desiredState":"%s"},"createIndex":{"desiredState":"%s"},"dropIndex":{"desiredState":"%s"}}}}' \
  "$DESIRED_STATE" \
  "$FORCE_LAST_GOOD_PLAN" \
  "$CREATE_INDEX" \
  "$DROP_INDEX")

az rest \
  --method patch \
  --uri "$URI" \
  --headers "Content-Type=application/json" \
  --body "$REQUEST_BODY" \
  --output table

echo "Automatic tuning configuration:"
az rest \
  --method get \
  --uri "$URI" \
  --query "properties.{desiredState:desiredState,actualState:actualState,forceLastGoodPlan:options.forceLastGoodPlan.actualState,createIndex:options.createIndex.actualState,dropIndex:options.dropIndex.actualState}" \
  --output table

echo "Database automatic tuning configured successfully."
