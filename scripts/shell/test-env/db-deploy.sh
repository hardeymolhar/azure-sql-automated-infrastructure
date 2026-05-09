#!/bin/bash

set -e

# echo "STEP 1 - Azure Login"
# ./login.sh

echo "STEP 2 - Deploy Key Vault"
bash -n key-vault.sh
bash -x key-vault.sh
#./key-vault.sh

echo "STEP 3 - Deploy Application VM"
bash -n app-vm.sh
bash -x app-vm.sh
#./app-vm.sh

# echo "STEP 4 - Configure Application VM"
# ./app-vm-config.sh

echo "STEP 5 - Deploy Azure SQL Database"
bash -n sql-db.sh
bash -x sql-db.sh
#./sql-db.sh

# echo "STEP 6 - Configure Entra Admin"
# ./set-entra-admin.sh

# echo "STEP 7 - SQL Initialization and Query Store Setup"
# ./sqlcmd-auth.sh

# echo "STEP 8 - Configure SQL Backup Policies"
# ./sqldb-backup.sh

# echo "STEP 9 - Enable SQL Auditing"
# ./sql-auditing.sh

# echo "STEP 10 - Configure Diagnostic Settings"
# ./diag-settings.sh

# echo "STEP 11 - Enable Automatic Tuning"
# ./sql-automatic-tuning.sh

# echo "STEP 12 - Execute Final Deployment"
# ./deploy.sh

# echo "STEP 13 - Run Ansible Automation"
# ./ansible-run.sh

# echo "DEPLOYMENT PIPELINE COMPLETED"