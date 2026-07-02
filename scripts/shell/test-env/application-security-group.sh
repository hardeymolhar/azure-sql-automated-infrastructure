#!/bin/bash
source "$(dirname "$0")/env.conf"
set -euo pipefail

# =========================================================
# APPLICATION SECURITY GROUP — all SQL VMs (Linux + Windows nodes)
# ---------------------------------------------------------
# Creates ONE Application Security Group (ASG) and attaches the NICs of ALL SQL
# VMs (the Linux node and both Windows SQL Server VMs) to it, so NSG rules can
# target the logical group (e.g. --destination-asgs <asg>) instead of per-IP /
# per-NIC entries. sql-engine-access.sh adds the inbound 1433 rule that consumes
# this ASG so the nodes can reach each other's engine over the public internet.
#
# Scope / placement:
#   - An ASG is a REGIONAL construct. All SQL VMs live in the same region
#     (centralindia) and VNet — the Linux node plus the two Windows nodes pinned
#     to availability zones 1/2 (WIN_VM_ZONE / WIN_VM_ZONE_2). Zones are *within*
#     a region, so one ASG spans all their NICs without issue.
#   - Members are NIC ip-configurations, not the VMs themselves.
#
# IMPORTANT: this script ONLY provisions the ASG and the membership. It does
# NOT rewire any NSG rules to consume the ASG — existing rules are untouched.
#
# Note: `az network nic ip-config update --application-security-groups` SETS
# (replaces) the ip-config's ASG list. These NICs currently carry no ASGs, so
# this is safe; if that ever changes, include the existing ASGs in the list.
# Ref (current CLI): learn.microsoft.com/cli/azure/network/asg ,
#                    learn.microsoft.com/cli/azure/network/nic/ip-config
# =========================================================

# Self-contained name (intentionally not added to env.conf, to avoid touching
# the shared config the rest of the codebase reads).
ASG_NAME="asg-win-$RESOURCE_SUFFIX"

# =========================================================
# HELPER FUNCTIONS
# =========================================================

resource_exists() {
  local resource_check_command="$1"

  if eval "$resource_check_command" >/dev/null 2>&1; then
    return 0
  else
    return 1
  fi
}

# =========================================================
# CREATE THE APPLICATION SECURITY GROUP
# =========================================================

if resource_exists "az network asg show --resource-group $RESOURCE_GROUP --name $ASG_NAME"; then
  echo -e "${YELLOW}ASG already exists. Skipping creation...${NC}"
else
  echo -e "${BLUE}Creating application security group ($ASG_NAME)...${NC}"

  az network asg create \
    --resource-group "$RESOURCE_GROUP" \
    --name "$ASG_NAME" \
    --location "$LOCATION"
fi

ASG_ID=$(az network asg show \
  --resource-group "$RESOURCE_GROUP" \
  --name "$ASG_NAME" \
  --query id \
  -o tsv)

# =========================================================
# ATTACH BOTH NODE NICs (across both zones) TO THE ASG
# ---------------------------------------------------------
# Resolve the NIC actually attached to each VM (rather than trusting configured
# names) and its primary ip-config, then add the ASG to that ip-config.
# =========================================================

for VM in "$VM_NAME" "$WIN_VM_NAME" "$WIN_VM_NAME_2"; do
  echo -e "${BLUE}Resolving NIC for VM $VM...${NC}"

  NIC=$(az vm nic list \
    --resource-group "$RESOURCE_GROUP" \
    --vm-name "$VM" \
    --query "[0].id" \
    -o tsv | awk -F'/' '{print $NF}')

  IPCONFIG=$(az network nic show \
    --resource-group "$RESOURCE_GROUP" \
    --name "$NIC" \
    --query "ipConfigurations[0].name" \
    -o tsv)

  # Skip if this ip-config is already a member (avoids needless updates and
  # keeps the run idempotent).
  if az network nic ip-config show \
      --resource-group "$RESOURCE_GROUP" \
      --nic-name "$NIC" \
      --name "$IPCONFIG" \
      --query "applicationSecurityGroups[].id" \
      -o tsv 2>/dev/null | grep -qx "$ASG_ID"; then
    echo -e "${YELLOW}$NIC ($IPCONFIG) already in $ASG_NAME. Skipping...${NC}"
    continue
  fi

  echo -e "${BLUE}Attaching $NIC ($IPCONFIG) to $ASG_NAME...${NC}"

  az network nic ip-config update \
    --resource-group "$RESOURCE_GROUP" \
    --nic-name "$NIC" \
    --name "$IPCONFIG" \
    --application-security-groups "$ASG_ID"
done

# =========================================================
# VALIDATION SUMMARY
# =========================================================

echo -e "${GREEN}==========================================${NC}"
echo -e "${GREEN}Application security group configured.${NC}"
echo -e "${GREEN}==========================================${NC}"
echo -e "${GREEN}ASG name:${NC}  $ASG_NAME"
echo -e "${GREEN}Members:${NC}   NICs of $VM_NAME (Linux) + $WIN_VM_NAME (zone $WIN_VM_ZONE) + $WIN_VM_NAME_2 (zone $WIN_VM_ZONE_2)"
echo ""
echo -e "${GREEN}Use it in an NSG rule with, e.g.:${NC}"
echo -e "  az network nsg rule create ... --destination-asgs $ASG_NAME"
echo -e "${GREEN}==========================================${NC}"
