#!/bin/bash
set -euo pipefail

source "$(dirname "$0")/env.conf"

# Dedicated inventory for this pipeline -- see AD_INVENTORY_FILE in env.conf.
# Prevents vm-res-ind-190.sh's concurrent vm-res-ind-190.sh run from
# truncating this script's inventory mid-flight.
INVENTORY_FILE="$AD_INVENTORY_FILE"

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

# winrm_connection_timeout=300: sets pywinrm's HTTP read timeout to value+10.
# At 120 (read window 130s), the first AD write on the freshly-promoted DC
# stalled past 130s (module cold-start + post-promotion churn) and the host was
# marked unreachable. 300 gives a 310s window per request; long-running tasks
# are unaffected (pywinrm polls in cycles, each poll only needs one response).
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
ansible_winrm_connection_timeout=300
ansible_winrm_read_timeout_sec: 130

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

# RESUME 2026-07-07: STEP 1 completed successfully in run vm-res-ind-190
# (forest sqlfci.local promoted, DNS forwarder set — recap ok=14 failed=0).
# Commented out to resume from STEP 2. Re-enable for a fresh sandbox.
# echo "STEP 1 - Promote the Primary Domain Controller (AD DS + DNS)..."

ANSIBLE_CONFIG="$PROJECT_ROOT/ansible.cfg" \
ansible-playbook "$PROJECT_ROOT/ansible/playbooks/configure-domain-controller.yml" \
  -i "$INVENTORY_FILE" \
  --extra-vars "
ad_domain_name=$AD_DOMAIN_NAME
ad_netbios_name=$AD_NETBIOS_NAME
ad_safe_mode_password=$AD_SAFE_MODE_PASSWORD
azure_dns_resolver=$AZURE_DNS_RESOLVER
"

echo "STEP 2 - Configure Active Directory..."

ANSIBLE_CONFIG="$PROJECT_ROOT/ansible.cfg" \
ansible-playbook "$PROJECT_ROOT/ansible/playbooks/configure-active-directory.yml" \
  -i "$INVENTORY_FILE" \
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
ansible_winrm_connection_timeout=300
EOT

echo "STEP 3 - Promote the Secondary Domain Controller..."

ANSIBLE_CONFIG="$PROJECT_ROOT/ansible.cfg" \
ansible-playbook "$PROJECT_ROOT/ansible/playbooks/configure-dc2.yml" \
  -i "$INVENTORY_FILE" \
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