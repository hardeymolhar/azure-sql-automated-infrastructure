#!/usr/bin/env bash
set -euo pipefail
source env.conf

# =============================================================================
# terraform_flat — working-directory reset
# -----------------------------------------------------------------------------
# Run this BEFORE ./init.sh. init.sh is not re-runnable on its own:
#
#   * it APPENDS `resource_group_name = "$primary_rg"` to terraform.tfvars with
#     `>>`, so a second run leaves the attribute defined twice and HCL refuses
#     to parse the file;
#   * it OVERWRITES backend.tf with a live azurerm backend block, so its own
#     first `terraform plan` is no longer the local-backend plan it assumes.
#
# This script undoes exactly those two mutations, drops the state/plan/lock
# artifacts (worthless past a timed lab), and leaves the directory freshly
# initialized on the local backend -- that last step is not optional, because
# init.sh never runs `terraform init` itself: its "Initializing..." banner sits
# above a `plan`, so without .terraform/ it fails on its first command.
#
#   ./cleanup.sh            confirm before discarding local state
#   ./cleanup.sh --force    no prompt, for unattended runs
#
# Scope: every path below is relative to this directory. Unlike
# scripts/shell/tfcleanup.sh, which sweeps the whole repo from the project root,
# this can never reach terraform/ or bootstrap/ state.
# =============================================================================

# Resolve shell directory
CLEAN_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"


FORCE=0
if [ "${1:-}" = "--force" ]; then
  FORCE=1
fi

# -----------------------------------------------------------------------------
# Guard: local state is the only record of what is deployed in Azure.
# -----------------------------------------------------------------------------
if [ -f terraform.tfstate ] && [ "$FORCE" -eq 0 ]; then
  echo -e "\033[33mterraform.tfstate exists in $CLEAN_DIR\033[0m"
  echo "Deleting it orphans any live Azure resources -- 'terraform destroy' will no longer be possible."
  read -r -p "Continue? [y/N] " reply || reply=""
  case "$reply" in
  [Yy]) ;;
  *)
    echo "Aborted."
    exit 1
    ;;
  esac
fi

echo -e "\033[33mResetting Terraform variables...\033[0m"

# init.sh appends resource_group_name with `>>`. Delete every copy (not just
# one) so repeated init.sh runs still leave exactly one line behind. The `^`
# anchor spares the commented discussion of the variable higher up the file.
if [ -f terraform.tfvars ]; then
  sed -i '' '/^resource_group_name[[:space:]]*=/d' terraform.tfvars
  echo "  terraform.tfvars: removed appended resource_group_name"
fi

# Restore backend.tf to its default local-backend configuration so the next
# bootstrap starts from a clean state.
if [ -f backend.tf ]; then
  cat > backend.tf <<'EOF'

EOF
  echo "  backend.tf: restored default backend configuration"
fi


echo -e "\033[33mRemoving Terraform state, plan and lock artifacts...\033[0m"

for artifact in terraform.tfstate terraform.tfstate.backup tfplan .terraform.lock.hcl; do
  if [ -e "$artifact" ]; then
    rm -f "$artifact"
    echo "  removed $artifact"
  fi
done

if [ -d .terraform ]; then
  rm -rf .terraform
  echo "  removed .terraform/"
fi

# backend.tf is fully commented out again, so this configures the LOCAL backend:
# no Azure auth needed (survives an expired az login), no state and no prior
# backend record on disk, therefore no migration prompt.
# echo -e "\033[33mRe-initializing Terraform (local backend)...\033[0m"
# terraform init

echo -e "\033[32mCleanup complete.\033[0m"





echo -e "\e[33mInitializing Terraform deployment...\e[0m"
terraform init


echo -e "\e[33mPlanning Terraform deployment...\e[0m"
terraform plan -out=tfplan -var-file=terraform.tfvars  -var="resource_group_name=$primary_rg" --parallelism=3

echo -e "\e[33mApplying Terraform configuration to set up backend storage...\e[0m"
terraform apply tfplan

STORAGE_ACCOUNT=$(az storage account list \
  --resource-group "$primary_rg" \
  --query "[0].name" \
  -o tsv)

cat <<EOF > backend.tf
terraform {
  backend "azurerm" {
    resource_group_name  = "${primary_rg}"
    storage_account_name = "$STORAGE_ACCOUNT"
    container_name       = "terraform-state-files"
    key                  = "bootstrap.tfstate"
  }
}
EOF


echo -e "\e[33mInitializing Terraform with the new backend...\e[0m"
printf "yes\n" | terraform init \
  --upgrade \
  --migrate-state 
# echo -e "\e[33mDeploying Resources in the flat file...\e[0m"

cd ../
./cleanup.sh
