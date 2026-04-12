#!/usr/bin/env bash
set -euo pipefail

# Resolve shell directory
INIT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"


cd "$INIT_DIR"


echo -e "\e[33mUpdating Terraform variables...\e[0m"


cat <<EOF >> ../../terraform/terraform.tfvars
rg = ["rg_sb_eastus_308450_1_177598821180",
  "rg_sb_centralindia_308450_3_177598821421",
"rg_sb_westus_308450_2_177598821322"]
EOF

cat <<EOF >> ../../bootstrap/terraform.tfvars
rg = ["rg_sb_eastus_308450_1_177598821180",
  "rg_sb_centralindia_308450_3_177598821421",
"rg_sb_westus_308450_2_177598821322"]
EOF

cd ../../bootstrap
echo -e "\e[33mInitializing Terraform without backend...\e[0m"
terraform init  --reconfigure

echo -e "\e[33mFormatting Terraform configuration files...\e[0m"
terraform  fmt -recursive

echo -e "\e[33mValidating Configuration...\e[0m"
terraform validate

: << 'IMPORT_BLOCK'

echo -e "\e[33mImporting Existing Storage Account Configuration into new state...\e[0m"

export MSYS_NO_PATHCONV=1
terraform import \
  -var-file="terraform.tfvars" \
  azurerm_storage_account.bootstrap \
  "/subscriptions/4f6a6eb9-27d0-4ed6-a31c-2bde135e2db6/resourceGroups/rg_sb_centralindia_308450_3_177570416050/providers/Microsoft.Storage/storageAccounts/tfstate225222"
export MSYS_NO_PATHCONV=1

terraform import \
  -var-file="terraform.tfvars" \
  'azurerm_storage_container.containers["scripts"]' \
  "https://tfstate225222.blob.core.windows.net/scripts"

terraform import \
  -var-file="terraform.tfvars" \
  'azurerm_storage_container.containers["terraform-state-files"]' \
  "https://tfstate225222.blob.core.windows.net/terraform-state-files"

IMPORT_BLOCK

echo -e "\e[33mPlanning Terraform deployment...\e[0m"
terraform  plan  -out=tfplan -var-file=terraform.tfvars --parallelism=3

echo -e "\e[33mApplying Terraform configuration to set up backend storage...\e[0m"
terraform  apply  tfplan

echo -e "\e[32mStorage account for Terraform state has been set up successfully.\e[0m"

echo -e "\e[33mUpdating bootstrap Terraform variables...\e[0m"


cat <<EOF > backend.tf
terraform {
  backend "azurerm" {

    resource_group_name  = "rg_sb_centralindia_308450_3_177598821421"
    storage_account_name = "tfstate225222"
    container_name       = "terraform-state-files"
    key                  = "bootstrap.tfstate"
  }
}
EOF




echo -e "\e[33mInitializing Bootstrap with the new backend...\e[0m"
terraform  init  --upgrade



cat <<EOF > ../terraform/backend.tf
terraform {
  backend "azurerm" {

    resource_group_name  = "rg_sb_centralindia_308450_3_177598821421"
    storage_account_name = "tfstate225222"
    container_name       = "terraform-state-files"
    key                  = "azuresql.tfstate"
  }
}
EOF


awk '
/backend[[:space:]]*=[[:space:]]*"azurerm"/ {
  print
  print ""
  print "  config = {"
  print "    resource_group_name  = \"rg_sb_centralindia_308450_3_177598821421\""
  print "    storage_account_name = \"tfstate225222\""
  print "    container_name       = \"terraform-state-files\""
  print "    key                  = \"bootstrap.tfstate\""
  print "  }"
  next
}

{ print }
' ../terraform/data.tf > tmp.tf && mv tmp.tf ../terraform/data.tf

echo -e "\e[33mInitializing Terraform with the new backend...\e[0m"
cd ../terraform
terraform init --upgrade



echo -e "\e[33mFormatting Terraform configuration files...\e[0m"
terraform fmt -recursive

echo -e "\e[33mValidating Configuration...\e[0m"
terraform validate

echo -e "\e[33mPlanning Terraform deployment...\e[0m"
terraform plan -out=tfplan -var-file=terraform.tfvars --parallelism=10

echo -e "\e[33mApplying Terraform plan...\e[0m"
terraform apply tfplan