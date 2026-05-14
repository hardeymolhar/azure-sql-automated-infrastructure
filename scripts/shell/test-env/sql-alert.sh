#!/bin/bash

set -euo pipefail
source "$(dirname "$0")/env.conf"
# =========================================================
# HELPER FUNCTIONS
# =========================================================

resource_exists() {
  local resource_check_command="$1"

  if eval "$resource_check_command" >/dev/null 2>&1; then
    return 0
  else
    return 1
  fi
}

# =========================================================
# INPUT VARIABLES
# =========================================================



# =========================================================
# RESOURCE IDS
# =========================================================

DATABASE_ID=$(az sql db show \
  --resource-group "$RESOURCE_GROUP" \
  --server "$SQL_SERVER_NAME" \
  --name "$DATABASE_NAME" \
  --query id \
  -o tsv)

# =========================================================
# CREATE ACTION GROUP
# =========================================================


if resource_exists "az monitor action-group show --name $ACTION_GROUP_NAME --resource-group $RESOURCE_GROUP"; then
  echo -e "${GREEN}Action Group already exists. Skipping creation...${NC}"
else
  echo -e "${YELLOW}Creating Azure Monitor Action Group...${NC}"

  az monitor action-group create \
    --name "$ACTION_GROUP_NAME" \
    --resource-group "$RESOURCE_GROUP" \
    --short-name "sqlalerts" \
    --action email sql-admin-alerts "$ALERT_EMAIL"
fi

ACTION_GROUP_ID=$(az monitor action-group show \
  --name "$ACTION_GROUP_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --query id \
  -o tsv)

# =========================================================
# DTU PERCENTAGE ALERT
# =========================================================


if resource_exists "az monitor metrics alert show --name $DTU_ALERT_NAME --resource-group $RESOURCE_GROUP"; then
  echo -e "${GREEN}Alert $DTU_ALERT_NAME already exists. Skipping creation...${NC}"
else
  echo -e "${YELLOW}Creating DTU Percentage alert...${NC}"

  az monitor metrics alert create \
    --name "$DTU_ALERT_NAME" \
    --resource-group "$RESOURCE_GROUP" \
    --scopes "$DATABASE_ID" \
    --description "Azure SQL DTU utilization exceeded 80 percent" \
    --condition "avg dtu_consumption_percent > 80" \
    --window-size 5m \
    --evaluation-frequency 1m \
    --severity 2 \
    --action "$ACTION_GROUP_ID"
fi

# =========================================================
# LOG IO PERCENTAGE ALERT
# =========================================================


if resource_exists "az monitor metrics alert show --name $LOG_IO_ALERT_NAME --resource-group $RESOURCE_GROUP"; then
  echo -e "${GREEN}Alert $LOG_IO_ALERT_NAME already exists. Skipping creation...${NC}"
else
  echo -e "${YELLOW}Creating Log IO Percentage alert...${NC}"

  az monitor metrics alert create \
    --name "$LOG_IO_ALERT_NAME" \
    --resource-group "$RESOURCE_GROUP" \
    --scopes "$DATABASE_ID" \
    --description "Azure SQL Log IO utilization exceeded 85 percent" \
    --condition "avg log_write_percent > 85" \
    --window-size 5m \
    --evaluation-frequency 1m \
    --severity 2 \
    --action "$ACTION_GROUP_ID"
fi

# =========================================================
# CPU PERCENTAGE ALERT
# =========================================================

SQL_CPU_ALERT_NAME="sql-cpu-percentage-alert"

if resource_exists "az monitor metrics alert show --name $SQL_CPU_ALERT_NAME --resource-group $RESOURCE_GROUP"; then
  echo -e "${GREEN}Alert $SQL_CPU_ALERT_NAME already exists. Skipping creation...${NC}"
else
  echo -e "${BLUE}Creating CPU Percentage alert...${NC}"

  az monitor metrics alert create \
    --name "$SQL_CPU_ALERT_NAME" \
    --resource-group "$RESOURCE_GROUP" \
    --scopes "$DATABASE_ID" \
    --description "Azure SQL CPU utilization exceeded 75 percent" \
    --condition "avg cpu_percent > 75" \
    --window-size 5m \
    --evaluation-frequency 1m \
    --severity 2 \
    --action "$ACTION_GROUP_ID"
fi

# =========================================================
# WORKERS PERCENTAGE ALERT
# =========================================================


if resource_exists "az monitor metrics alert show --name $SQL_WORKERS_ALERT_NAME --resource-group $RESOURCE_GROUP"; then
  echo -e "${GREEN}Alert $SQL_WORKERS_ALERT_NAME already exists. Skipping creation...${NC}"
else
  echo -e "${YELLOW}Creating Workers Percentage alert...${NC}"

  az monitor metrics alert create \
    --name "$SQL_WORKERS_ALERT_NAME" \
    --resource-group "$RESOURCE_GROUP" \
    --scopes "$DATABASE_ID" \
    --description "Azure SQL worker utilization exceeded 80 percent" \
    --condition "avg workers_percent > 80" \
    --window-size 5m \
    --evaluation-frequency 1m \
    --severity 2 \
    --action "$ACTION_GROUP_ID"
fi

# =========================================================
# DEADLOCK ALERT
# =========================================================


if resource_exists "az monitor metrics alert show --name $DEADLOCK_ALERT_NAME --resource-group $RESOURCE_GROUP"; then
  echo -e "${GREEN}Alert $DEADLOCK_ALERT_NAME already exists. Skipping creation...${NC}"
else
  echo -e "${YELLOW}Creating Deadlock alert...${NC}"

  az monitor metrics alert create \
    --name "$DEADLOCK_ALERT_NAME" \
    --resource-group "$RESOURCE_GROUP" \
    --scopes "$DATABASE_ID" \
    --description "Azure SQL deadlock detected" \
    --condition "total deadlock > 0" \
    --window-size 5m \
    --evaluation-frequency 1m \
    --severity 1 \
    --action "$ACTION_GROUP_ID"
fi

# =========================================================
# SESSIONS PERCENTAGE ALERT
# =========================================================

if resource_exists "az monitor metrics alert show --name $SQL_SESSIONS_ALERT_NAME --resource-group $RESOURCE_GROUP"; then
  echo -e "${GREEN}Alert $SQL_SESSIONS_ALERT_NAME already exists. Skipping creation...${NC}"
else
  echo -e "${YELLOW}Creating Sessions Percentage alert...${NC}"

  az monitor metrics alert create \
    --name "$SQL_SESSIONS_ALERT_NAME" \
    --resource-group "$RESOURCE_GROUP" \
    --scopes "$DATABASE_ID" \
    --description "Azure SQL session utilization exceeded 70 percent" \
    --condition "avg sessions_percent > 70" \
    --window-size 5m \
    --evaluation-frequency 1m \
    --severity 2 \
    --action "$ACTION_GROUP_ID"
fi

echo "================================================"
echo -e "${GREEN}AZURE SQL ALERT CONFIGURATION COMPLETE${NC}"
echo "================================================"