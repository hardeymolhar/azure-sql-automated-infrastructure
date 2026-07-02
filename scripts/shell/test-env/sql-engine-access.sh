#!/bin/bash
source "$(dirname "$0")/env.conf"
set -euo pipefail

# =========================================================
# SQL ENGINE PEER ACCESS — inbound 1433 over the public internet
# ---------------------------------------------------------
# Opens TCP 1433 INBOUND to every SQL VM so the Linux node and the Windows nodes
# can reach each other's engine over the public internet (SSMS-style), plus your
# own workstation. This is the "separate step" application-security-group.sh
# anticipates (it provisions the ASG + membership but does NOT add NSG rules).
#
# Hybrid by design — IP allowlist SOURCE, ASG DESTINATION:
#   - SOURCE must be an IP allowlist. An ASG groups VMs INSIDE the VNet, so it can
#     never match an internet source: SSMS (or another VM hitting a public IP)
#     arrives with a PUBLIC source IP that is not an ASG member. Scoped to the
#     client IP + each SQL VM's public IP; NEVER 0.0.0.0/0 — same scoping as the
#     SSH/RDP/WinRM rules and the project's no-public-exposure posture.
#   - DESTINATION is the ASG (asg-win-<suffix>). One rule covers every SQL VM in
#     the group, regardless of count or IP.
#
# Prereqs: the SQL VMs exist (public IPs assigned) and their NICs are in the ASG
# (run application-security-group.sh first — it now includes the Linux NIC, so
# the destination-asg rule also covers the Linux engine). Idempotent.
# =========================================================

ASG_NAME="asg-win-$RESOURCE_SUFFIX"
RULE_NAME="Allow-SQL-Engine-Peers"
RULE_PRIORITY=1021 # between Allow-SQL-Client-IP (1020) and Allow-LB-Probe (1030)

resource_exists() {
  local resource_check_command="$1"
  if eval "$resource_check_command" >/dev/null 2>&1; then
    return 0
  else
    return 1
  fi
}

# =========================================================
# RESOLVE THE ASG (must already exist)
# =========================================================
if ! resource_exists "az network asg show --resource-group $RESOURCE_GROUP --name $ASG_NAME"; then
  echo -e "${RED}ASG $ASG_NAME not found. Run application-security-group.sh first.${NC}"
  exit 1
fi

ASG_ID=$(az network asg show \
  --resource-group "$RESOURCE_GROUP" \
  --name "$ASG_NAME" \
  --query id \
  -o tsv)

# =========================================================
# BUILD THE SOURCE ALLOWLIST — client IP + each SQL VM's public IP
# ---------------------------------------------------------
# Public IPs are resolved at runtime. A VM that isn't up yet is skipped (with a
# warning) so a partial sandbox run still produces a working allowlist for the
# VMs that do exist.
# =========================================================
SOURCE_IPS=("$CLIENT_IP")

for VM in "$VM_NAME" "$WIN_VM_NAME" "$WIN_VM_NAME_2"; do
  PIP=$(az vm show \
    --resource-group "$RESOURCE_GROUP" \
    --name "$VM" \
    -d \
    --query publicIps \
    -o tsv 2>/dev/null || true)

  if [ -n "$PIP" ]; then
    echo -e "${BLUE}$VM public IP: $PIP${NC}"
    SOURCE_IPS+=("$PIP")
  else
    echo -e "${YELLOW}Could not resolve a public IP for $VM (not created yet?). Skipping.${NC}"
  fi
done

echo -e "${GREEN}Inbound 1433 source allowlist:${NC} ${SOURCE_IPS[*]}"

# =========================================================
# CREATE/UPDATE THE INBOUND 1433 RULE ON EACH SQL VM's NSG
# ---------------------------------------------------------
# destination = the ASG, so the rule only admits traffic to SQL-VM NICs in the
# group. Additive: leaves the existing per-VM Allow-SQL-Client-IP (1020) in place.
# =========================================================
for NSG in "$NSG_NAME" "$WIN_NSG_NAME" "$WIN2_NSG_NAME"; do
  if ! resource_exists "az network nsg show --resource-group $RESOURCE_GROUP --name $NSG"; then
    echo -e "${YELLOW}NSG $NSG not found. Skipping...${NC}"
    continue
  fi

  if resource_exists "az network nsg rule show --resource-group $RESOURCE_GROUP --nsg-name $NSG --name $RULE_NAME"; then
    echo -e "${YELLOW}Rule $RULE_NAME exists on $NSG. Refreshing sources...${NC}"
    az network nsg rule update \
      --resource-group "$RESOURCE_GROUP" \
      --nsg-name "$NSG" \
      --name "$RULE_NAME" \
      --source-address-prefixes "${SOURCE_IPS[@]}" \
      --destination-asgs "$ASG_ID"
  else
    echo -e "${BLUE}Creating $RULE_NAME on $NSG...${NC}"
    az network nsg rule create \
      --resource-group "$RESOURCE_GROUP" \
      --nsg-name "$NSG" \
      --name "$RULE_NAME" \
      --priority "$RULE_PRIORITY" \
      --direction Inbound \
      --access Allow \
      --protocol Tcp \
      --source-address-prefixes "${SOURCE_IPS[@]}" \
      --source-port-ranges "*" \
      --destination-port-ranges "$SQL_PORT" \
      --destination-asgs "$ASG_ID"
  fi
done

echo -e "${GREEN}==========================================${NC}"
echo -e "${GREEN}SQL engine peer access configured (inbound 1433).${NC}"
echo -e "${GREEN}==========================================${NC}"
echo -e "${GREEN}Destination ASG:${NC} $ASG_NAME"
echo -e "${GREEN}Allowed sources:${NC} ${SOURCE_IPS[*]}"
echo -e "${GREEN}NSGs updated:${NC}    $NSG_NAME, $WIN_NSG_NAME, $WIN2_NSG_NAME"
echo -e "${GREEN}==========================================${NC}"
