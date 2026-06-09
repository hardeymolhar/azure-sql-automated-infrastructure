#!/bin/bash
# =========================================================
# SANDBOX ENVIRONMENT NOTES
# =========================================================
# This deployment targets the Whizlabs Azure sandbox environment,
# which is time-bound and provisioned dynamically.
#
# Resource names, suffixes, and identifiers may vary between sessions,
# but the deployment workflow and orchestration process remain consistent.
#
# This approach intentionally optimizes for rapid deployment and
# reproducibility within constrained sandbox time limits.
# =========================================================

set -euo pipefail

# Run from the script's own directory so the ./*.sh calls below resolve
# regardless of the caller's working directory.
cd "$(dirname "$0")"

source "./env.conf"

# echo -e "${BLUE}Baseline:  variables configuration pre deployment...${NC}"
# ./var-config.sh

# echo -e "${BLUE}STEP 1 - Deploy Storage Account${NC}"
# ./storage.sh

# echo -e "${BLUE}STEP 2 - Deploy Key Vault and Encryption Keys${NC}"
# ./key-vault.sh

# echo -e "${BLUE}STEP 3 - Configure Disk Encryption Set and Encrypted Disks (Linux)${NC}"
# ./encrypted-mgd-disks.sh

# echo -e "${BLUE}STEP 4 - Deploy Linux Application VM (creates + attaches its disks)${NC}"
# ./app-vm.sh

# echo -e "${BLUE} Deploy Bastion Host for secure connectivity to VMs (Linux + Windows)${NC}"
# ./bastion.sh

echo -e "${BLUE}STEP 5 - Deploy Windows SQL Server VM (SQL Node 1, Zone 1)${NC}"
./win-sql-vm.sh

echo -e "${BLUE}STEP 6 - Create and Attach Encrypted Disks to SQL Node 1${NC}"
./win-encrypted-disks.sh

echo -e "${BLUE}STEP 7 - Deploy Windows SQL Server VM (SQL Node 2, Zone 2)${NC}"
./win-sql-vm-2.sh

echo -e "${BLUE}STEP 8 - Create and Attach Encrypted Disks to SQL Node 2${NC}"
./win-encrypted-disks-2.sh

echo -e "${BLUE}STEP 9 - Configure VMs Using Ansible (drives, packages, SQL Server)${NC}"
./vm-config.sh


# echo -e "${BLUE}STEP 8 - Deploy Azure SQL Database${NC}"
# ./sql-db.sh

# echo -e "${BLUE}STEP 9 - Configure Azure SQL Alerts and Notifications${NC}"
# ./sql-alert.sh

# echo -e "${BLUE}STEP 10 - Configure Entra Administrator${NC}"
# ./set-entra-admin.sh

# echo -e "${BLUE}STEP 11 - Enable Azure SQL Auditing${NC}"
# ./sql-auditing.sh

# echo -e "${BLUE}STEP 12 - Configure Azure SQL Diagnostic Settings${NC}"
# ./diag-settings.sh

# echo -e "${BLUE}STEP 13 - Configure Azure SQL Backup Policies${NC}"
# ./sqldb-backup.sh

# echo -e "${YELLOW}Waiting 2 minutes for Always Encrypted and CMK dependencies to propagate...${NC}"
# sleep 120

# echo -e "${BLUE}STEP 14 - Initialize Database and Configure Query Store${NC}"
# ./identity.sh



# echo "Fetching Azure outputs..."

# LIN_VM_IP=$(az vm list-ip-addresses \
#   --resource-group "$(az group list --query '[1].name' -o tsv)" \
#   --name "vm-stg-ind-224" \
#   --query "[0].virtualMachine.network.publicIpAddresses[0].ipAddress" \
#   -o tsv)

# LIN_VM_NAME=$(az vm list \
#   --resource-group "$(az group list --query '[1].name' -o tsv)" \
#   --query "[?contains(name, '$RESOURCE_SUFFIX')].name | [0]" \
#   -o tsv)

# SQL_SERVER_NAME=$(az sql server list \
#   --resource-group "$(az group list --query '[1].name' -o tsv)" \
#   --query "[?contains(name, '$RESOURCE_SUFFIX')].name | [0]" \
#   -o tsv)
  

# DATABASE_NAME=$(az sql db list \
#   --resource-group "$(az group list --query '[1].name' -o tsv)" \
#   --server "$SQL_SERVER_NAME" \
#   --query "[?contains(name, 'demo')].name | [0]" \
#   -o tsv)


# # echo -e "${YELLOW}Running SQL Config playbook...${NC}"

# # ANSIBLE_CONFIG=$PROJECT_ROOT/ansible.cfg ansible-playbook \
# #   $PROJECT_ROOT/ansible/playbooks/controlled-workload.yml \
# #   -i $INVENTORY_FILE \
# #   --extra-vars "sql_server_name=$SQL_SERVER_NAME \
# #   database_name=$DATABASE_NAME \
# #   worker_count=2 \
# #   insert_batch_size=8 \
# #   max_cycles=120 \
# #   workload_duration_minutes=30 \
# #   after_commit_delay_ms=3000 \
# #   after_select_delay_ms=5000"

# # echo -e "${GREEN}DEPLOYMENT PIPELINE COMPLETED${NC}"


# echo -e "${YELLOW}Running SQL Config playbook...${NC}"

# ANSIBLE_CONFIG=$PROJECT_ROOT/ansible.cfg ansible-playbook \
#   $PROJECT_ROOT/ansible/playbooks/concurrency-v2.yml \
#   -i $INVENTORY_FILE \
#   --extra-vars "sql_server_name=$SQL_SERVER_NAME \
#   database_name=$DATABASE_NAME \
#   worker_count=40 \
#   reporting_workers=12 \
#   deadlock_workers=6 \
#   session_holder_count=220 \
#   max_batches=0 \
#   min_batch_size=750 \
#   max_batch_size=2500 \
#   workload_duration_minutes=60 \
#   batch_delay_ms=0"

# echo -e "${GREEN}DEPLOYMENT PIPELINE COMPLETED${NC}"

