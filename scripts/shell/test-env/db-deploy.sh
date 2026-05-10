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


echo "STEP 7 - SQL Initialization and Query Store Setup"
./identity.sh


# echo "STEP 11 - Configure CMK with Azure Key Vault"
# ./../../powershell/encrypted-cek.ps1



# echo "DEPLOYMENT PIPELINE COMPLETED"