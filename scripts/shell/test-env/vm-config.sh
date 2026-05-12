#!/bin/bash
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color 


PROJECT_ROOT="$(git rev-parse --show-toplevel)"

INVENTORY_FILE="$PROJECT_ROOT/inventory.ini"

echo -e "${YELLOW}Fetching Azure outputs...${NC}"

LIN_VM_IP=$(az vm list-ip-addresses \
  --resource-group "$(az group list --query '[1].name' -o tsv)" \
  --name "vm-99999990" \
  --query "[0].virtualMachine.network.publicIpAddresses[0].ipAddress" \
  -o tsv)

LIN_VM_NAME=$(az vm list \
  --resource-group "$(az group list --query '[1].name' -o tsv)" \
  --query "[?contains(name, '-99999990')].name | [0]" \
  -o tsv)



  

echo "Updating Ansible inventory..."

cat > $INVENTORY_FILE <<EOT
[rhel_vm]
$LIN_VM_NAME ansible_host=$LIN_VM_IP




[rhel_vm:vars]
ansible_user=sqladmin
ansible_ssh_private_key_file=~/.ssh/ssh_key/vm-key/vm-key
EOT


echo "RHEL VM Disks and Storage Configuration..."
ANSIBLE_CONFIG=$PROJECT_ROOT/ansible.cfg ansible-playbook $PROJECT_ROOT/ansible/playbooks/disk-config.yml


echo "Installing RHEL VM packages for Azure SQL connectivity..."
ANSIBLE_CONFIG=$PROJECT_ROOT/ansible.cfg ansible-playbook $PROJECT_ROOT/ansible/playbooks/vm-pkg.yml





echo "Pipeline completed successfully."
