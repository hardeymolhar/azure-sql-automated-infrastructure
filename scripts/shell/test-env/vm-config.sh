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
$WIN_VM_NAME ansible_host=$WIN_VM_PUBLIC_IP
$WIN_VM_NAME_2 ansible_host=$WIN_VM_PUBLIC_IP_2

[windows_vm:vars]
ansible_connection=winrm
ansible_user=$ADMIN_USERNAME
ansible_password=$ADMIN_PASSWORD
ansible_port=$WIN_WINRM_PORT
ansible_winrm_transport=ntlm
ansible_winrm_server_cert_validation=ignore
EOT


# echo "RHEL VM Disks and Storage Configuration..."
# ANSIBLE_CONFIG=$PROJECT_ROOT/ansible.cfg \
#   ansible-playbook $PROJECT_ROOT/ansible/playbooks/dbdrive-configuration.yml


# echo "Installing RHEL VM packages for Azure SQL connectivity..."
# ANSIBLE_CONFIG=$PROJECT_ROOT/ansible.cfg ansible-playbook $PROJECT_ROOT/ansible/playbooks/vm-pkg.yml

# export OBJC_DISABLE_INITIALIZE_FORK_SAFETY=YES
# echo "Windows VM Disks and Storage Configuration (both nodes)..."
# ANSIBLE_CONFIG="$PROJECT_ROOT/ansible.cfg" ansible-playbook \
#   "$PROJECT_ROOT/ansible/playbooks/windows-dbdrive-configuration.yml"

echo "Installing and configuring SQL Server (ready-to-connect) + SSMS on the Windows VM..."
ANSIBLE_CONFIG="$PROJECT_ROOT/ansible.cfg" ansible-playbook \
  "$PROJECT_ROOT/ansible/playbooks/sql-server-on-windows.yml" \
  --extra-vars "sa_password=$ADMIN_PASSWORD app_login=$SQL_LOGIN app_login_password=$SQL_LOGIN_PASSWORD win_sql_login=$WIN_SQL_LOGIN win_sql_login_password=$WIN_SQL_LOGIN_PASSWORD sql_installer_url=$SQL_INSTALLER_URL"


echo "Pipeline completed successfully."
