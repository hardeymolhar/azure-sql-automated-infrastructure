#!/bin/bash
set -euo pipefail


echo "Initializing Terraform providers..."

terraform -chdir=../terraform init -upgrade

echo "Fetching Terraform outputs..."

WIN_VM_IP=$(terraform -chdir=../terraform output -raw db_vm_public_ip)
LIN_VM_IP=$(terraform -chdir=../terraform output -raw linux_vm_public_ip)

echo "Updating Ansible inventory..."

cat > ../ansible/inventory.ini <<EOT
[linux_vm]
azure-vm-01 ansible_host=$LIN_VM_IP

[linux_vm:vars]
ansible_user=azureuser
ansible_ssh_private_key_file=/home/hardeymolhar/.ssh/dev/dev-key
ansible_connection=ssh

[windows]
win-dev-vm-1 ansible_host=$WIN_VM_IP

[windows:vars]
ansible_user=azureuser
ansible_password=r3P1iKa5x_123
ansible_connection=winrm
ansible_port=5985
ansible_winrm_transport=ntlm
ansible_winrm_server_cert_validation=ignore
EOT

echo "Running Ansible playbook..."
ANSIBLE_CONFIG=../ansible/ansible.cfg \
ansible-playbook \
../ansible/sql-server-on-rhel.yml \
--ask-vault-pass

echo "Pipeline completed successfully."