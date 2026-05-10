#!/bin/bash

set -euo pipefail

echo "Creating temporary service principal..."

SP_JSON=$(az ad sp create-for-rbac --name "lab-sp")

AZURE_CLIENT_ID=$(echo "$SP_JSON" | jq -r '.appId')
AZURE_CLIENT_SECRET=$(echo "$SP_JSON" | jq -r '.password')
AZURE_TENANT_ID=$(echo "$SP_JSON" | jq -r '.tenant')

AZURE_SUBSCRIPTION_ID=$(az account show --query id -o tsv)

echo "Temporary identity created."

read -p "Press ENTER to authenticate and continue..."

az login \
  --service-principal \
  --username "$AZURE_CLIENT_ID" \
  --password "$AZURE_CLIENT_SECRET" \
  --tenant "$AZURE_TENANT_ID" \
  >/dev/null

az account set \
  --subscription "$AZURE_SUBSCRIPTION_ID"

unset SP_JSON

echo "Authentication successful."