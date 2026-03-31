#!/bin/bash
set -euo pipefail




echo "Fetching Terraform outputs..."

WIN_VM_IP=$(terraform -chdir=../terraform output -raw db_vm_public_ip)
LIN_VM_IP=$(terraform -chdir=../terraform output -raw linux_vm_public_ip)

echo "Updating Ansible inventory..."

cat > ../ansible/inventory/inventory.ini <<EOT
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


echo "Initializing data disk on Windows VM..."
ANSIBLE_CONFIG=../ansible/ansible.cfg \
ansible-playbook \
../ansible/playbooks/win-disk-init.yml 

echo "Running RHEL disk initialization playbook..."
ANSIBLE_CONFIG=../ansible/ansible.cfg \
ansible-playbook \
../ansible/playbooks/linux-disk-config.yml

echo "Running SQL Server on RHEL Ansible playbook..."
ANSIBLE_CONFIG=../ansible/ansible.cfg \
ansible-playbook \
../ansible/playbooks/sql-server-on-rhel.yml




echo "Pipeline completed successfully."