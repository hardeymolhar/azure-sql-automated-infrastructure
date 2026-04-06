#!/usr/bin/env bash
set -euo pipefail

# Set environment (default = dev)
ENV=${1:-dev}

echo -e "\e[33mEnvironment: $ENV\e[0m"


# ----------------------------------------
# DYNAMIC BACKEND
# ----------------------------------------


terraform -chdir=../../terraform init -reconfigure \
-backend-config="key=${ENV}.tfstate"

echo -e "\e[33mFormatting Terraform files...\e[0m"
terraform -chdir=../../terraform fmt -recursive

echo -e "\e[33mValidating Terraform configuration...\e[0m"
terraform -chdir=../../terraform validate

echo -e "\e[33mCreating execution plan...\e[0m"
terraform -chdir=../../terraform plan \
  -var-file="terraform.tfvars" \
  -parallelism=20 \
  -out=tfplan



echo -e "\e[33mApplying Terraform plan...\e[0m"
terraform -chdir=../../terraform apply tfplan

# ----------------------------------------
# ANSIBLE
# ----------------------------------------

echo -e "\e[33mRunning Ansible configuration...\e[0m"
dos2unix ../../ansible/ansible-run.sh
../../ansible/ansible-run.sh

: '
Dynamic Backend (Recommended for CI/CD)
Use when:
- You want explicit control
- Multi-environment deployments
- Production pipelines

Example:
terraform init \
  -backend-config="key=${ENV}.tfstate"
'
