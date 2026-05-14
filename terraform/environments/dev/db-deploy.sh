#!/bin/bash
set -euo pipefail



source "$(dirname "$0")/env.conf"

echo -e "${BLUE}Baseline:  variables configuration pre deployment...${NC}"
./var-config.sh

echo -e "${BLUE}STEP 1 - Deploy Key Vault${NC}"
./key-vault.sh

echo -e "${BLUE}STEP 2 - Configure Disk Encryption Set and Encrypted Disks${NC}"
./encrypted-mgd-disks.sh

echo -e "${BLUE}STEP 3  - Deploy Application VM${NC}"
./app-vm.sh

echo -e "${BLUE}STEP 4 - Configure Application VM Using Ansible${NC}"
./vm-config.sh

echo -e "${BLUE}STEP 5 - Deploy Azure SQL Database${NC}"
./sql-db.sh

echo -e "${BLUE}STEP 6 - Configure Azure SQL Alerts and Notifications${NC}"
./sql-alert.sh

echo -e "${BLUE}STEP 7 - Configure Entra Administrator${NC}"
./set-entra-admin.sh

echo -e "${BLUE}STEP 8 - Enable Azure SQL Auditing${NC}"
./sql-auditing.sh

echo -e "${BLUE}STEP 9 - Configure Azure SQL Diagnostic Settings${NC}"
./diag-settings.sh

echo -e "${BLUE}STEP 10 - Configure Azure SQL Backup Policies${NC}"
./sqldb-backup.sh

echo -e "${YELLOW}Waiting 2 minutes for Always Encrypted and CMK dependencies to propagate...${NC}"
sleep 120

echo -e "${BLUE}STEP 11 - Initialize Database and Configure Query Store${NC}"
./identity.sh

# =========================================================
# SANDBOX ENVIRONMENT NOTES
# =========================================================
#
# This deployment targets the Whizlabs Azure sandbox environment,
# which is time-bound and provisioned dynamically.
#
# Resource names, suffixes, and identifiers may vary between sessions,
# but the deployment workflow and orchestration process remain consistent.
#
# The sandbox creates resource groups in deterministic order.
# Index [1] consistently maps to the preferred deployment resource group
# used for this lab environment.
#
# This approach intentionally optimizes for rapid deployment and
# reproducibility within constrained sandbox time limits.
# =========================================================


echo "Fetching Azure outputs..."

LIN_VM_IP=$(az vm list-ip-addresses \
  --resource-group "$(az group list --query '[1].name' -o tsv)" \
  --name "vm-9r5-1n4-77" \
  --query "[0].virtualMachine.network.publicIpAddresses[0].ipAddress" \
  -o tsv)

LIN_VM_NAME=$(az vm list \
  --resource-group "$(az group list --query '[1].name' -o tsv)" \
  --query "[?contains(name, '$RESOURCE_SUFFIX')].name | [0]" \
  -o tsv)

SQL_SERVER_NAME=$(az sql server list \
  --resource-group "$(az group list --query '[1].name' -o tsv)" \
  --query "[?contains(name, '$RESOURCE_SUFFIX')].name | [0]" \
  -o tsv)
  

DATABASE_NAME=$(az sql db list \
  --resource-group "$(az group list --query '[1].name' -o tsv)" \
  --server "$SQL_SERVER_NAME" \
  --query "[?contains(name, 'demo')].name | [0]" \
  -o tsv)


echo -e "${YELLOW}Running SQL Config playbook...${NC}"

ANSIBLE_CONFIG=$PROJECT_ROOT/ansible.cfg ansible-playbook \
  $PROJECT_ROOT/ansible/playbooks/transactions-v2.yml \
  -i $INVENTORY_FILE \
  --extra-vars "sql_server_name=$SQL_SERVER_NAME \
  database_name=$DATABASE_NAME \
  worker_count=140 \
  max_batches=250 \
  min_batch_size=2000 \
  max_batch_size=10000 \
  batch_delay_ms=0"

echo -e "${GREEN}DEPLOYMENT PIPELINE COMPLETED${NC}"
