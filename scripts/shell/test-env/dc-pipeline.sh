#!/bin/bash
set -euo pipefail

source "$(dirname "$0")/env.conf"

echo -e "${YELLOW}Fetching Azure outputs...${NC}"

# =========================================================
# PRIMARY DOMAIN CONTROLLER
# =========================================================

DC_VM_PUBLIC_IP=$(az vm list-ip-addresses \
  --resource-group "$RESOURCE_GROUP" \
  --name "$DC_VM_NAME" \
  --query "[0].virtualMachine.network.publicIpAddresses[0].ipAddress" \
  -o tsv)

echo "Updating Ansible inventory for the Primary Domain Controller..."

cat > "$INVENTORY_FILE" <<EOT
[domain_controller]
$DC_VM_NAME ansible_host=$DC_VM_PUBLIC_IP

[domain_controller:vars]
ansible_connection=winrm
ansible_user=$ADMIN_USERNAME
ansible_password=$ADMIN_PASSWORD
ansible_port=$HTTPS_WIN_WINRM_PORT
ansible_winrm_scheme=https
ansible_winrm_transport=ntlm
ansible_winrm_server_cert_validation=ignore
ansible_winrm_connection_timeout=120
EOT

# # =========================================================
# # ACTIVE DIRECTORY DEPLOYMENT PIPELINE
# # ---------------------------------------------------------
# # Execution order:
# #
# #   STEP 1  Build the forest root Domain Controller
# #   STEP 2  Configure Active Directory
# #            - Organizational Units
# #            - Security Groups
# #            - Service Accounts
# #
# #   STEP 3  Build the secondary Domain Controller
# #
# # At completion both Domain Controllers replicate the
# # same Active Directory database.
# # =========================================================

echo "STEP 1 - Promote the Primary Domain Controller (AD DS + DNS)..."

ANSIBLE_CONFIG="$PROJECT_ROOT/ansible.cfg" \
ansible-playbook "$PROJECT_ROOT/ansible/playbooks/configure-domain-controller.yml" \
  --extra-vars "
ad_domain_name=$AD_DOMAIN_NAME
ad_netbios_name=$AD_NETBIOS_NAME
ad_safe_mode_password=$AD_SAFE_MODE_PASSWORD
azure_dns_resolver=$AZURE_DNS_RESOLVER
"

echo "STEP 2 - Configure Active Directory..."

ANSIBLE_CONFIG="$PROJECT_ROOT/ansible.cfg" \
ansible-playbook "$PROJECT_ROOT/ansible/playbooks/configure-active-directory.yml" \
  --extra-vars "
ad_domain_name=$AD_DOMAIN_NAME
ad_safe_mode_password=$AD_SAFE_MODE_PASSWORD
"

# =========================================================
# SECONDARY DOMAIN CONTROLLER
# =========================================================

DC2_VM_PUBLIC_IP=$(az vm list-ip-addresses \
  --resource-group "$RESOURCE_GROUP" \
  --name "$DC2_VM_NAME" \
  --query "[0].virtualMachine.network.publicIpAddresses[0].ipAddress" \
  -o tsv)

echo "Updating Ansible inventory for the Secondary Domain Controller..."

cat > "$INVENTORY_FILE" <<EOT
[secondary_domain_controller]
$DC2_VM_NAME ansible_host=$DC2_VM_PUBLIC_IP

[secondary_domain_controller:vars]
ansible_connection=winrm
ansible_user=$ADMIN_USERNAME
ansible_password=$ADMIN_PASSWORD
ansible_port=$HTTPS_WIN_WINRM_PORT
ansible_winrm_scheme=https
ansible_winrm_transport=ntlm
ansible_winrm_server_cert_validation=ignore
ansible_winrm_connection_timeout=120
EOT

echo "STEP 3 - Promote the Secondary Domain Controller..."

ANSIBLE_CONFIG="$PROJECT_ROOT/ansible.cfg" \
ansible-playbook "$PROJECT_ROOT/ansible/playbooks/configure-dc2.yml" \
  --extra-vars "
ad_domain_name=$AD_DOMAIN_NAME
ad_netbios_name=$AD_NETBIOS_NAME
ad_safe_mode_password=$AD_SAFE_MODE_PASSWORD
azure_dns_resolver=$AZURE_DNS_RESOLVER
domain_admin_user=$DOMAIN_ADMIN_USER
dc_private_ip=$DC_PRIVATE_IP
dc2_private_ip=$DC2_PRIVATE_IP
domain_admin_password=$AD_SAFE_MODE_PASSWORD
"

echo
echo "=========================================================="
echo " Active Directory deployment completed successfully."
echo "=========================================================="