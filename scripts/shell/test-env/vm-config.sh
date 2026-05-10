#!/bin/bash
set -euo pipefail


PROJECT_ROOT="$(git rev-parse --show-toplevel)"

INVENTORY_FILE="$PROJECT_ROOT/inventory.ini"

echo "Fetching Azure outputs..."

LIN_VM_IP=$(az vm list-ip-addresses \
  --resource-group "$(az group list --query '[1].name' -o tsv)" \
  --name "vm-234809" \
  --query "[0].virtualMachine.network.publicIpAddresses[0].ipAddress" \
  -o tsv)


echo "Updating Ansible inventory..."

cat > $INVENTORY_FILE <<EOT
[rhel_vm]
rhel_vm ansible_host=$LIN_VM_IP




[rhel_vm:vars]
ansible_user=sqladmin
ansible_ssh_private_key_file=/Users/mac/.ssh/ssh_key/vm-key/vm-key
EOT


echo "Installing RHEL VM packages for Azure SQL connectivity..."
ANSIBLE_CONFIG=$PROJECT_ROOT/ansible.cfg 

ansible-playbook $PROJECT_ROOT/ansible/playbooks/sql-vm-packages.yml





echo "Pipeline completed successfully."