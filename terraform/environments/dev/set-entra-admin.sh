#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/env.conf"

# =========================================================
# VALIDATE RESOURCE GROUP
# =========================================================

if ! az group exists --name "$RESOURCE_GROUP" | grep -q true; then

    echo -e "${RED}ERROR: Resource group '$RESOURCE_GROUP' does not exist.${NC}"

    exit 1

fi


# =========================================================
# SET MICROSOFT ENTRA ADMIN
# =========================================================

echo "Configuring Microsoft Entra admin..."

if az sql server ad-admin list \
    --resource-group "$RESOURCE_GROUP" \
    --server "$SQL_SERVER_NAME" \
    --query "[?objectId=='$OBJECT_ID'] | [0]" \
    -o tsv | grep -q "$OBJECT_ID"
then
    echo -e "${GREEN}Microsoft Entra admin already configured.${NC}"
else
    az sql server ad-admin create \
        --resource-group "$RESOURCE_GROUP" \
        --server "$SQL_SERVER_NAME" \
        --display-name "$DISPLAY_NAME" \
        --object-id "$OBJECT_ID"
fi

echo ""

echo -e "${GREEN}Microsoft Entra admin configured successfully.${NC}"

echo -e "${BLUE}Server      : $SQL_SERVER_NAME${NC}"
echo -e "${BLUE}Admin User  : $DISPLAY_NAME${NC}"