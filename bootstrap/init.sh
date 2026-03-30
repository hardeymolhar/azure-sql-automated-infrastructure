#!/usr/bin/env bash
set -euo pipefail

# Resolve bootstrap directory
INIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"


cd "$INIT_DIR"


echo -e "\e[33mInitializing Terraform without backend...\e[0m"
terraform init -backend=false

echo -e "\e[33mFormatting Terraform configuration files...\e[0m"
terraform fmt -recursive

echo -e "\e[33mValidating Configuration...\e[0m"
terraform validate

: << 'IMPORT_BLOCK'

echo -e "\e[33mImporting Existing Storage Account Configuration into new state...\e[0m"

export MSYS_NO_PATHCONV=1
terraform import \
  -var-file="variables.tfvars" \
  azurerm_storage_account.bootstrap \
  "/subscriptions/4f6a6eb9-27d0-4ed6-a31c-2bde135e2db6/resourceGroups/rg_sb_westus_308450_2_177419938938/providers/Microsoft.Storage/storageAccounts/tfstate225222"

export MSYS_NO_PATHCONV=1

terraform import \
  -var-file="variables.tfvars" \
  'azurerm_storage_container.containers["scripts"]' \
  "https://tfstate225222.blob.core.windows.net/scripts"

terraform import \
  -var-file="variables.tfvars" \
  'azurerm_storage_container.containers["terraform-state-files"]' \
  "https://tfstate225222.blob.core.windows.net/terraform-state-files"

IMPORT_BLOCK

echo -e "\e[33mPlanning Terraform deployment...\e[0m"
terraform plan -out=tfplan -var-file=variables.tfvars --parallelism=3

echo -e "\e[33mApplying Terraform configuration to set up backend storage...\e[0m"
terraform apply tfplan 

echo -e "\e[32mStorage account for Terraform state has been set up successfully.\e[0m"