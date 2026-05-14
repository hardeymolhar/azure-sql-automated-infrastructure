#!/bin/bash
set -euo pipefail

source "$(dirname "$0")/env.conf"


echo -e "${YELLOW}Fetching Azure outputs...${NC}"

LIN_VM_IP=$(az vm list-ip-addresses \
  --resource-group "$(az group list --query '[1].name' -o tsv)" \
  --name "$VM_NAME" \
  --query "[0].virtualMachine.network.publicIpAddresses[0].ipAddress" \
  -o tsv)


  

echo "Updating Ansible inventory..."

cat > $INVENTORY_FILE <<EOT
[rhel_vm]
$VM_NAME ansible_host=$LIN_VM_IP




[rhel_vm:vars]
ansible_user=sqladmin
ansible_ssh_private_key_file=~/.ssh/ssh_key/vm_key/vm_key
EOT


echo "RHEL VM Disks and Storage Configuration..."
ANSIBLE_CONFIG=$PROJECT_ROOT/ansible.cfg ansible-playbook $PROJECT_ROOT/ansible/playbooks/dbdrive-configuration.yml


echo "Installing RHEL VM packages for Azure SQL connectivity..."
ANSIBLE_CONFIG=$PROJECT_ROOT/ansible.cfg ansible-playbook $PROJECT_ROOT/ansible/playbooks/vm-pkg.yml





# echo "Pipeline completed successfully."
