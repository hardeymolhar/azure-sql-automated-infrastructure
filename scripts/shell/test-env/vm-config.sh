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




# Storage account key for the WSFC Cloud Witness (and, later, the lab-file SAS).
# Fetched once here and reused so configure-wsfc.yml gets it before the SQL plays.
STORAGE_ACCOUNT_KEY=$(az storage account keys list \
  --account-name "$STORAGE_ACCOUNT_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --query "[0].value" \
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


# =========================================================
# ANSIBLE PIPELINE (dependency-ordered)
# ---------------------------------------------------------
# Active Directory is now a first-class dependency, so the DC is configured FIRST
# and every later stage assumes AD + DNS exist. Order:
#   1. configure-domain-controller.yml  (AD DS + DNS + forest)
#   2. dbdrive-configuration.yml        (RHEL disks)
#   3. vm-res-ind-332.yml                        (RHEL packages)
#   4. windows-dbdrive-configuration.yml (Windows disks + DNS + domain join)
#   5. configure-wsfc.yml               (WSFC + Cloud Witness quorum)
#   6. sql-server-on-rhel.yml           (SQL on RHEL)
#   7. sql-server-on-windows.yml        (SQL + FCI/AG on Windows)
# =========================================================



# echo "STEP 3 - Configuring RHEL VM disks and storage (/u02 /u03 /u04 /u05)..."
# ANSIBLE_CONFIG="$PROJECT_ROOT/ansible.cfg" \
#   ansible-playbook "$PROJECT_ROOT/ansible/playbooks/dbdrive-configuration.yml"


# echo "STEP 4 - Installing RHEL VM packages for Azure SQL connectivity..."
# ANSIBLE_CONFIG="$PROJECT_ROOT/ansible.cfg" \
#   ansible-playbook "$PROJECT_ROOT/ansible/playbooks/vm-pkg.yml"


echo "STEP 5 - Windows disks + DNS + domain join (both nodes)..."
ANSIBLE_CONFIG="$PROJECT_ROOT/ansible.cfg" \
ansible-playbook "$PROJECT_ROOT/ansible/playbooks/windows-dbdrive-configuration.yml" \
  --extra-vars "ad_domain_name=$AD_DOMAIN_NAME \
dc_private_ip=$DC_PRIVATE_IP \
domain_admin_user=$DOMAIN_ADMIN_USER \
domain_admin_password=$ADMIN_PASSWORD \
win_vm_name=$WIN_VM_NAME \
dc_private_ip=$DC_PRIVATE_IP \
dc2_private_ip=$DC2_PRIVATE_IP \
win_vm_name_2=$WIN_VM_NAME_2"


echo "STEP 6 - Building the Windows Server Failover Cluster + Cloud Witness quorum..."
# WSFC creation connects as the DOMAIN admin (nodes are domain-joined by now), not
# the per-node local sqladmin — see the play header for why.
ANSIBLE_CONFIG="$PROJECT_ROOT/ansible.cfg" \
ansible-playbook "$PROJECT_ROOT/ansible/playbooks/configure-wsfc.yml" \
  --extra-vars "wsfc_cluster_ip=$WSFC_CLUSTER_IP \
witness_sa=$WITNESS_STORAGE_ACCOUNT \
witness_key=$STORAGE_ACCOUNT_KEY \
domain_admin_user=$DOMAIN_ADMIN_USER \
domain_admin_password=$ADMIN_PASSWORD"
echo "Generating a SAS download URL for the DP-300 lab archive..."
# Read+write SAS for the already-uploaded blob (storage.sh put it there with the
# account key). Both the RHEL VM (get_url) and the Windows VMs (win_get_url) pull
# it over HTTPS — far faster than streaming ~114 MB over the Ansible connection.
# Short-lived (7 days); GNU date (-d) with a BSD date (-v) fallback so it works on
# the Linux CI image and the macOS control node alike. Reuses STORAGE_ACCOUNT_KEY
# fetched near the top (also used for the WSFC Cloud Witness).
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
  --extra-vars "vault_mssql_sa_password=$ADMIN_PASSWORD lab_blob_sas_url=$LAB_BLOB_SAS_URL"


echo "STEP 8 - Installing and configuring SQL Server (ready-to-connect) + SSMS on the Windows VM..."
ANSIBLE_CONFIG="$PROJECT_ROOT/ansible.cfg" \
ansible-playbook "$PROJECT_ROOT/ansible/playbooks/sql-server-on-windows.yml" \
  --extra-vars "sa_password=$ADMIN_PASSWORD \
app_login=$SQL_LOGIN \
app_login_password=$SQL_LOGIN_PASSWORD \
win_sql_login=$WIN_SQL_LOGIN \
win_sql_login_password=$WIN_SQL_LOGIN_PASSWORD \
sql_installer_url=$SQL_INSTALLER_URL \
lab_blob_sas_url=$LAB_BLOB_SAS_URL \
ad_domain_name=$AD_DOMAIN_NAME \
ad_safe_mode_password=$AD_SAFE_MODE_PASSWORD"

echo "Pipeline completed successfully."
