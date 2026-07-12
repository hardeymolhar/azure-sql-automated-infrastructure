#!/bin/bash
set -euo pipefail

source "$(dirname "$0")/env.conf"

# Dedicated inventory for this pipeline -- see LINUX_INVENTORY_FILE in env.conf.
INVENTORY_FILE="$LINUX_INVENTORY_FILE"


LIN_VM_IP=$(az vm list-ip-addresses \
  --resource-group "$(az group list --query '[1].name' -o tsv)" \
  --name "$VM_NAME" \
  --query "[0].virtualMachine.network.publicIpAddresses[0].ipAddress" \
  -o tsv)


echo "Updating Ansible inventory..."

cat > "$INVENTORY_FILE" <<EOT
[rhel_vm]
$VM_NAME ansible_host=$LIN_VM_IP

[rhel_vm:vars]
ansible_user=sqladmin
ansible_ssh_private_key_file=$SSH_PRIVATE_KEY_PATH
EOT

# RESUME 2026-07-07: STEP 3 completed successfully in run vm-res-ind-190
# (/u02-/u05 partitioned, formatted XFS — recap ok=11 failed=0).
# Commented out to resume from STEP 4. Re-enable for a fresh sandbox.
echo "STEP 3 - Configuring RHEL VM disks and storage (/u02 /u03 /u04 /u05)..."
ANSIBLE_CONFIG="$PROJECT_ROOT/ansible.cfg" \
  ansible-playbook "$PROJECT_ROOT/ansible/playbooks/dbdrive-configuration.yml" \
  -i "$INVENTORY_FILE"



echo "STEP 4 - Installing RHEL VM packages for Azure SQL connectivity..."
ANSIBLE_CONFIG="$PROJECT_ROOT/ansible.cfg" \
  ansible-playbook "$PROJECT_ROOT/ansible/playbooks/vm-pkg.yml" \
  -i "$INVENTORY_FILE"


echo "Generating a SAS download URL for the DP-300 lab archive..."
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

echo "STEP 7 - Installing and configuring SQL Server 2022 on the RHEL VM..."
ANSIBLE_CONFIG="$PROJECT_ROOT/ansible.cfg" \
ansible-playbook "$PROJECT_ROOT/ansible/playbooks/sql-server-on-rhel.yml" \
  -i "$INVENTORY_FILE" \
  --extra-vars "vault_mssql_sa_password=$ADMIN_PASSWORD lab_blob_sas_url=$LAB_BLOB_SAS_URL"
