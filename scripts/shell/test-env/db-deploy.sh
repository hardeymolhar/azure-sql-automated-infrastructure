PROJECT_ROOT="$(git rev-parse --show-toplevel)"

INVENTORY_FILE="$PROJECT_ROOT/inventory.ini"


#!/bin/bash

set -e

# echo "STEP 1 - Azure Login"
# ./login.sh


# echo "STEP 2 - Deploy Key Vault"
# ./key-vault.sh

# echo "STEP 3 - Deploy Application VM"
# ./app-vm.sh

# echo "STEP 4 - Configure Application VM Using Ansible"
# ./vm-config.sh

# echo "STEP 5 - Deploy Azure SQL Database"
# ./sql-db.sh

# echo "STEP 6 - Configure Entra Admin"
# ./set-entra-admin.sh

# echo "STEP 9 - Enable SQL Auditing"
# ./sql-auditing.sh

# echo "STEP 11 - Configure Diagnostic Settings"
# ./diag-settings.sh

# echo "STEP 8 - Configure SQL Backup Policies"
# ./sqldb-backup.sh
# echo "Configure AEK Waiting 2 minutes before continuing."
# sleep 120


# echo "STEP 7 - SQL Initialization and Query Store Setup"
# ./identity.sh


echo "Fetching Azure outputs..."

LIN_VM_IP=$(az vm list-ip-addresses \
  --resource-group "$(az group list --query '[1].name' -o tsv)" \
  --name "vm-2348112" \
  --query "[0].virtualMachine.network.publicIpAddresses[0].ipAddress" \
  -o tsv)

LIN_VM_NAME=$(az vm list \
  --resource-group "$(az group list --query '[1].name' -o tsv)" \
  --query "[?contains(name, '-2348112')].name | [0]" \
  -o tsv)

SQL_SERVER_NAME=$(az sql server list \
  --resource-group "$(az group list --query '[1].name' -o tsv)" \
  --query "[?contains(name, '-2348112')].name | [0]" \
  -o tsv)
  

DATABASE_NAME=$(az sql db list \
  --resource-group "$(az group list --query '[1].name' -o tsv)" \
  --server "$SQL_SERVER_NAME" \
  --query "[?contains(name, 'demo')].name | [0]" \
  -o tsv)


echo "STEP 8 - Configure CMK using PowerShell..."

echo "Running SQL Config playbook..."

ANSIBLE_CONFIG=$PROJECT_ROOT/ansible.cfg ansible-playbook \
  $PROJECT_ROOT/ansible/playbooks/transactions.yml \
  -i $INVENTORY_FILE \
  --extra-vars "sql_server_name=$SQL_SERVER_NAME database_name=$DATABASE_NAME"

echo "DEPLOYMENT PIPELINE COMPLETED"