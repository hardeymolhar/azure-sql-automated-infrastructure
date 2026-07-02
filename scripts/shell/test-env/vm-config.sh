#!/bin/bash
set -euo pipefail

source "$(dirname "$0")/env.conf"


echo -e "${YELLOW}Fetching Azure outputs...${NC}"

LIN_VM_IP=$(az vm list-ip-addresses \
  --resource-group "$(az group list --query '[1].name' -o tsv)" \
  --name "$VM_NAME" \
  --query "[0].virtualMachine.network.publicIpAddresses[0].ipAddress" \
  -o tsv)

WIN_VM_PUBLIC_IP=$(az vm list-ip-addresses \
  --resource-group "$RESOURCE_GROUP" \
  --name "$WIN_VM_NAME" \
  --query "[0].virtualMachine.network.publicIpAddresses[0].ipAddress" \
  -o tsv)

# SQL Node 2 (Zone 2)
WIN_VM_PUBLIC_IP_2=$(az vm list-ip-addresses \
  --resource-group "$RESOURCE_GROUP" \
  --name "$WIN_VM_NAME_2" \
  --query "[0].virtualMachine.network.publicIpAddresses[0].ipAddress" \
  -o tsv)


echo "Updating Ansible inventory..."

cat > "$INVENTORY_FILE" <<EOT
[rhel_vm]
$VM_NAME ansible_host=$LIN_VM_IP

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


echo "Generating a SAS download URL for the DP-300 lab archive..."
# Read+write SAS for the already-uploaded blob (storage.sh put it there with the
# account key). Both the RHEL VM (get_url) and the Windows VMs (win_get_url) pull
# it over HTTPS — far faster than streaming ~114 MB over the Ansible connection.
# Short-lived (7 days); GNU date (-d) with a BSD date (-v) fallback so it works on
# the Linux CI image and the macOS control node alike. Minted here, before the
# RHEL play, so both that play and the Windows play below receive the same URL.
STORAGE_ACCOUNT_KEY=$(az storage account keys list \
  --account-name "$STORAGE_ACCOUNT_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --query "[0].value" \
  -o tsv)

SAS_EXPIRY=$(date -u -d '+7 days' '+%Y-%m-%dT%H:%MZ' 2>/dev/null || date -u -v+7d '+%Y-%m-%dT%H:%MZ')

LAB_BLOB_SAS_URL=$(az storage blob generate-sas \
  --account-name "$STORAGE_ACCOUNT_NAME" \
  --container-name "$CONTAINER_NAME" \
  --name "$BLOB_NAME" \
  --permissions rw \
  --expiry "$SAS_EXPIRY" \
  --account-key "$STORAGE_ACCOUNT_KEY" \
  --https-only \
  --full-uri \
  -o tsv)

echo "Installing and configuring SQL Server 2022 on the RHEL VM..."
ANSIBLE_CONFIG="$PROJECT_ROOT/ansible.cfg" \
ansible-playbook "$PROJECT_ROOT/ansible/playbooks/sql-server-on-rhel.yml" \
  --extra-vars "vault_mssql_sa_password=$ADMIN_PASSWORD lab_blob_sas_url=$LAB_BLOB_SAS_URL"



echo "Installing and configuring SQL Server (ready-to-connect) + SSMS on the Windows VM..."
ANSIBLE_CONFIG="$PROJECT_ROOT/ansible.cfg" \
ansible-playbook "$PROJECT_ROOT/ansible/playbooks/sql-server-on-windows.yml" \
  --extra-vars "sa_password=$ADMIN_PASSWORD app_login=$SQL_LOGIN app_login_password=$SQL_LOGIN_PASSWORD win_sql_login=$WIN_SQL_LOGIN win_sql_login_password=$WIN_SQL_LOGIN_PASSWORD sql_installer_url=$SQL_INSTALLER_URL lab_blob_sas_url=$LAB_BLOB_SAS_URL"


echo "Pipeline completed successfully."
