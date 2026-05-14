#!/usr/bin/env bash

set -euo pipefail

# Configure Azure SQL Database automatic tuning at database level.
# Official docs:
# - https://learn.microsoft.com/azure/azure-sql/database/automatic-tuning-enable
# - https://learn.microsoft.com/sql/t-sql/statements/alter-database-transact-sql-set-options
# - https://learn.microsoft.com/sql/relational-databases/performance/monitoring-performance-by-using-the-query-store
# - https://learn.microsoft.com/sql/relational-databases/system-catalog-views/sys-database-automatic-tuning-mode-transact-sql
# - https://learn.microsoft.com/sql/relational-databases/system-catalog-views/sys-database-automatic-tuning-options-transact-sql
#
# Microsoft docs note that active geo-replication should be configured on
# the primary database only; tuning actions replicate to geo-secondaries.
#
# Override values when running if needed:
#   RESOURCE_GROUP="my-rg" SERVER_NAME="my-server" DB_NAME="my-db" ./sql-automatic-tuning.sh
#   AUTH_MODE="sql" ADMIN_USER="sqladmin" ADMIN_PASSWORD="..." ./sql-automatic-tuning.sh

RESOURCE_GROUP="${RESOURCE_GROUP:-$(az group list --query "[1].name" -o tsv)}"
SERVER_NAME="${SERVER_NAME:-$(az sql server list \
  --resource-group "$RESOURCE_GROUP" \
  --query "[?contains(name, '-234806')].name | [0]" \
  -o tsv)}"
SERVER_NAME="$(printf '%s' "$SERVER_NAME" | tr -d '[:space:]')"
DB_NAME="${DB_NAME:-demo-db}"
AUTH_MODE="${AUTH_MODE:-azcli}"
ADMIN_USER="${ADMIN_USER:-}"

# Database automatic tuning states: AUTO, INHERIT, CUSTOM.
DESIRED_STATE="${DESIRED_STATE:-CUSTOM}"

# Option states: On, Off, Default.
FORCE_LAST_GOOD_PLAN="${FORCE_LAST_GOOD_PLAN:-ON}"
CREATE_INDEX="${CREATE_INDEX:-ON}"
DROP_INDEX="${DROP_INDEX:-OFF}"
ENSURE_QUERY_STORE_READ_WRITE="${ENSURE_QUERY_STORE_READ_WRITE:-true}"
QUERY_STORE_MAX_STORAGE_MB="${QUERY_STORE_MAX_STORAGE_MB:-2048}"

to_upper() {
  printf '%s' "$1" | tr '[:lower:]' '[:upper:]'
}

DESIRED_STATE="$(to_upper "$DESIRED_STATE")"
FORCE_LAST_GOOD_PLAN="$(to_upper "$FORCE_LAST_GOOD_PLAN")"
CREATE_INDEX="$(to_upper "$CREATE_INDEX")"
DROP_INDEX="$(to_upper "$DROP_INDEX")"
AUTH_MODE="$(to_upper "$AUTH_MODE")"
ENSURE_QUERY_STORE_READ_WRITE="$(to_upper "$ENSURE_QUERY_STORE_READ_WRITE")"

require_one_of() {
  local name="$1"
  local value="$2"
  shift 2

  for allowed in "$@"; do
    if [[ "$value" == "$allowed" ]]; then
      return 0
    fi
  done

  echo "ERROR: $name must be one of: $*"
  echo "Current value: $value"
  exit 1
}

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

require_one_of "DESIRED_STATE" "$DESIRED_STATE" AUTO INHERIT CUSTOM
require_one_of "FORCE_LAST_GOOD_PLAN" "$FORCE_LAST_GOOD_PLAN" ON OFF DEFAULT
require_one_of "CREATE_INDEX" "$CREATE_INDEX" ON OFF DEFAULT
require_one_of "DROP_INDEX" "$DROP_INDEX" ON OFF DEFAULT
require_one_of "AUTH_MODE" "$AUTH_MODE" AZCLI ENTRA SQL
require_one_of "ENSURE_QUERY_STORE_READ_WRITE" "$ENSURE_QUERY_STORE_READ_WRITE" TRUE FALSE

if [[ "$AUTH_MODE" == "ENTRA" && -z "$ADMIN_USER" ]]; then
  ADMIN_USER="${ADMIN_USER:-$(az ad signed-in-user show --query userPrincipalName -o tsv)}"
fi

if [[ "$AUTH_MODE" == "SQL" ]]; then
  if [[ -z "$ADMIN_USER" ]]; then
    echo "ERROR: ADMIN_USER is required when AUTH_MODE=sql."
    exit 1
  fi

  if [[ -z "${ADMIN_PASSWORD:-}" ]]; then
    echo "ERROR: ADMIN_PASSWORD is required when AUTH_MODE=sql."
    exit 1
  fi
fi

if ! [[ "$QUERY_STORE_MAX_STORAGE_MB" =~ ^[0-9]+$ ]] || (( QUERY_STORE_MAX_STORAGE_MB < 1 )); then
  echo "ERROR: QUERY_STORE_MAX_STORAGE_MB must be a positive integer."
  exit 1
fi

if [[ -x "/opt/homebrew/bin/sqlcmd" ]]; then
  SQLCMD_BIN="/opt/homebrew/bin/sqlcmd"
else
  SQLCMD_BIN="sqlcmd"
fi

if ! command -v "$SQLCMD_BIN" >/dev/null 2>&1; then
  echo "ERROR: sqlcmd is not installed or not in PATH."
  echo "Install sqlcmd, then rerun this script."
  exit 1
fi

echo "Resource group:         $RESOURCE_GROUP"
echo "SQL server:             $SERVER_NAME"
echo "SQL FQDN:               ${SERVER_NAME}.database.windows.net"
echo "Database:               $DB_NAME"
echo "Auth mode:              $AUTH_MODE"
echo "Admin user:             ${ADMIN_USER:-<Azure CLI signed-in identity>}"
echo "Desired tuning state:   $DESIRED_STATE"
echo "Force last good plan:   $FORCE_LAST_GOOD_PLAN"
echo "Create index:           $CREATE_INDEX"
echo "Drop index:             $DROP_INDEX"
echo "Ensure Query Store RW:  $ENSURE_QUERY_STORE_READ_WRITE"

SQL_SERVER_FQDN="${SERVER_NAME}.database.windows.net"

SQLCMD_ARGS=(
  -S "$SQL_SERVER_FQDN"
  -d "$DB_NAME"
  -N
  -b
  -r 1
)

case "$AUTH_MODE" in
  AZCLI)
    SQLCMD_ARGS+=(--authentication-method ActiveDirectoryAzCli)
    ;;
  ENTRA)
    SQLCMD_ARGS+=(-G -U "$ADMIN_USER")
    ;;
  SQL)
    SQLCMD_ARGS+=(--authentication-method SqlPassword -U "$ADMIN_USER" -P "$ADMIN_PASSWORD")
    ;;
esac

echo "Checking Query Store state..."
"$SQLCMD_BIN" "${SQLCMD_ARGS[@]}" -h -1 -W -Q "
SET NOCOUNT ON;
SELECT 'Query Store actual state: ' + actual_state_desc
FROM sys.database_query_store_options;
"

if [[ "$ENSURE_QUERY_STORE_READ_WRITE" == "TRUE" ]]; then
  echo "Ensuring Query Store is READ_WRITE..."
  "$SQLCMD_BIN" "${SQLCMD_ARGS[@]}" -Q "
ALTER DATABASE CURRENT SET QUERY_STORE = ON;
ALTER DATABASE CURRENT SET QUERY_STORE (
  OPERATION_MODE = READ_WRITE,
  MAX_STORAGE_SIZE_MB = $QUERY_STORE_MAX_STORAGE_MB
);
"

  echo "Query Store state after configuration:"
  "$SQLCMD_BIN" "${SQLCMD_ARGS[@]}" -h -1 -W -Q "
SET NOCOUNT ON;
SELECT
  'Query Store desired state: ' + desired_state_desc,
  'Query Store actual state: ' + actual_state_desc,
  'Query Store max storage MB: ' + CONVERT(varchar(20), max_storage_size_mb)
FROM sys.database_query_store_options;
"
fi

echo "Configuring automatic tuning..."
"$SQLCMD_BIN" "${SQLCMD_ARGS[@]}" -Q "
ALTER DATABASE CURRENT SET AUTOMATIC_TUNING = $DESIRED_STATE;
ALTER DATABASE CURRENT SET AUTOMATIC_TUNING (
  FORCE_LAST_GOOD_PLAN = $FORCE_LAST_GOOD_PLAN,
  CREATE_INDEX = $CREATE_INDEX,
  DROP_INDEX = $DROP_INDEX
);
"

echo "Automatic tuning mode:"
"$SQLCMD_BIN" "${SQLCMD_ARGS[@]}" -Q "
SET NOCOUNT ON;
SELECT
  desired_state_desc,
  actual_state_desc
FROM sys.database_automatic_tuning_mode;
"

echo "Automatic tuning options:"
"$SQLCMD_BIN" "${SQLCMD_ARGS[@]}" -Q "
SET NOCOUNT ON;
SELECT
  name,
  desired_state_desc,
  actual_state_desc,
  reason_desc
FROM sys.database_automatic_tuning_options
ORDER BY name;
"

echo "Database automatic tuning configured successfully."



SUBSCRIPTION_ID="$(az account show --query id -o tsv)"

az rest \
  --method GET \
  --url "https://management.azure.com/subscriptions/$SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.Sql/servers/$SERVER_NAME/databases/$DB_NAME/automaticTuning/current?api-version=2021-11-01-preview"
