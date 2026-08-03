#!/bin/bash
set -euo pipefail

# =========================================================
# COLORS
# =========================================================

YELLOW='\033[1;33m'
NC='\033[0m'

# =========================================================
# TERRAFORM OUTPUTS
# ---------------------------------------------------------
# The terraform_flat counterpart of scripts/shell/test-env/vm-config.sh. Same
# job, same inventory, same playbooks -- the only difference is where the values
# come from.
#
# The original sourced env.conf and then ran four live `az` queries: two
# `az vm list-ip-addresses` for the node IPs, `az storage account keys list`, and
# `az storage blob generate-sas`. Each was a fresh lookup against whatever was in
# the subscription at that moment, so this script could configure a DIFFERENT
# estate than the one just deployed. Terraform is now the source of truth: every
# value below is read from the state of the apply that created it.
#
# env.conf is deliberately NOT sourced. It executes `az group list`,
# `az ad signed-in-user show`, `curl ipify` and an `az vm list-ip-addresses` at
# source time -- and that last one aborts the script under `set -e` whenever the
# Linux VM does not exist, which is the default in this root.
# =========================================================

PROJECT_ROOT="$(git rev-parse --show-toplevel)"
TF_DIR="$PROJECT_ROOT/terraform_flat"
INVENTORY_FILE="$PROJECT_ROOT/inventory.ini"

echo -e "${YELLOW}Fetching Terraform outputs...${NC}"

LIN_VM_NAME=$(terraform -chdir="$TF_DIR" output -raw linux_vm_name)
LIN_VM_IP=$(terraform -chdir="$TF_DIR" output -raw linux_vm_public_ip)

# SQL Node 1 (Zone 1)
WIN_VM_NAME=$(terraform -chdir="$TF_DIR" output -raw windows_vm_name)
WIN_VM_PUBLIC_IP=$(terraform -chdir="$TF_DIR" output -raw windows_vm_public_ip)

# SQL Node 2 (Zone 2)
WIN_VM_NAME_2=$(terraform -chdir="$TF_DIR" output -raw windows_vm_name_2)
WIN_VM_PUBLIC_IP_2=$(terraform -chdir="$TF_DIR" output -raw windows_vm_public_ip_2)

ADMIN_USERNAME=$(terraform -chdir="$TF_DIR" output -raw admin_username)
ADMIN_PASSWORD=$(terraform -chdir="$TF_DIR" output -raw admin_password)
HTTPS_WIN_WINRM_PORT=$(terraform -chdir="$TF_DIR" output -raw winrm_https_port)
SSH_PRIVATE_KEY_PATH=$(terraform -chdir="$TF_DIR" output -raw ssh_private_key_path)

SQL_LOGIN=$(terraform -chdir="$TF_DIR" output -raw sql_login)
WIN_SQL_LOGIN=$(terraform -chdir="$TF_DIR" output -raw win_sql_login)
SQL_INSTALLER_URL=$(terraform -chdir="$TF_DIR" output -raw sql_installer_url)

# env.conf set both of these to $ADMIN_PASSWORD; preserved.
SQL_LOGIN_PASSWORD="$ADMIN_PASSWORD"
WIN_SQL_LOGIN_PASSWORD="$ADMIN_PASSWORD"

# Ansible's winrm connection plugin forks; without this macOS aborts the run.
export OBJC_DISABLE_INITIALIZE_FORK_SAFETY=YES


echo "Updating Ansible inventory..."

cat > "$INVENTORY_FILE" <<EOT
[rhel_vm]

[rhel_vm:vars]
ansible_user=sqladmin
ansible_ssh_private_key_file=$SSH_PRIVATE_KEY_PATH
[windows_vm]
$WIN_VM_NAME   ansible_host=$WIN_VM_PUBLIC_IP
$WIN_VM_NAME_2 ansible_host=$WIN_VM_PUBLIC_IP_2

[windows_vm:vars]
ansible_connection=winrm
ansible_user=$ADMIN_USERNAME
ansible_password=$ADMIN_PASSWORD
ansible_port=$HTTPS_WIN_WINRM_PORT
ansible_winrm_scheme=https
ansible_winrm_transport=ntlm
ansible_winrm_server_cert_validation=ignore
ansible_winrm_connection_timeout=120
ansible_winrm_read_timeout_sec=300
EOT


echo "Configuring RHEL VM disks and storage (/u02 /u03 /u04 /u05)..."
ANSIBLE_CONFIG="$PROJECT_ROOT/ansible.cfg" \
  ansible-playbook "$PROJECT_ROOT/ansible/playbooks/dbdrive-configuration.yml"


echo "Installing RHEL VM packages for Azure SQL connectivity..."
ANSIBLE_CONFIG="$PROJECT_ROOT/ansible.cfg" \
  ansible-playbook "$PROJECT_ROOT/ansible/playbooks/vm-pkg.yml"


echo "Windows VM Disks and Storage Configuration (both nodes)..."
ANSIBLE_CONFIG="$PROJECT_ROOT/ansible.cfg" \
ansible-playbook "$PROJECT_ROOT/ansible/playbooks/windows-dbdrive-configuration.yml"


echo "Reading the SAS download URL for the DP-300 lab archive..."
# Read+write SAS for the already-uploaded blob (storage.tf put it there with the
# account key). Both the RHEL VM (get_url) and the Windows VMs (win_get_url) pull
# it over HTTPS -- far faster than streaming ~114 MB over the Ansible connection.
# Terraform mints it declaratively against a time_rotating window (see data.tf),
# which replaces the account-key lookup and the GNU/BSD `date` arithmetic this
# block used to need. Empty when docs/lab-files/ was absent at apply time.
LAB_BLOB_SAS_URL=$(terraform -chdir="$TF_DIR" output -raw lab_blob_sas_url)

echo "Installing and configuring SQL Server 2022 on the RHEL VM..."
ANSIBLE_CONFIG="$PROJECT_ROOT/ansible.cfg" \
ansible-playbook "$PROJECT_ROOT/ansible/playbooks/sql-server-on-rhel.yml" \
  --extra-vars "vault_mssql_sa_password=$ADMIN_PASSWORD lab_blob_sas_url=$LAB_BLOB_SAS_URL"



echo "Installing and configuring SQL Server (ready-to-connect) + SSMS on the Windows VM..."
ANSIBLE_CONFIG="$PROJECT_ROOT/ansible.cfg" \
ansible-playbook "$PROJECT_ROOT/ansible/playbooks/sql-server-on-windows.yml" \
  --extra-vars "sa_password=$ADMIN_PASSWORD app_login=$SQL_LOGIN app_login_password=$SQL_LOGIN_PASSWORD win_sql_login=$WIN_SQL_LOGIN win_sql_login_password=$WIN_SQL_LOGIN_PASSWORD sql_installer_url=$SQL_INSTALLER_URL lab_blob_sas_url=$LAB_BLOB_SAS_URL"


echo "Pipeline completed successfully."
