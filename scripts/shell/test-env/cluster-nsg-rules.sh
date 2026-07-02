#!/bin/bash
source "$(dirname "$0")/env.conf"
set -euo pipefail

# =========================================================
# WSFC CLUSTER NSG RULES — intra-cluster traffic (ASG source + ASG destination)
# ---------------------------------------------------------
# Creates asg-sqlcluster, attaches both Windows SQL node NICs, then adds five
# inbound NSG rules on BOTH Windows NSGs for cluster-internal communication.
#
# Why ASG-to-ASG (not IP-to-IP)?
#   ASG membership travels with the NIC inside the VNet, so source=asg-sqlcluster
#   matches cluster nodes regardless of their current IP. Works because cluster
#   traffic stays inside the VNet (no internet traversal).
#
# Ports covered:
#   1433  — SQL Server engine (AG mirroring traffic + client)
#   5022  — HADR endpoint (database mirroring / AG log-shipping stream)
#   3343  — WSFC cluster heartbeat (both TCP and UDP — protocol = *)
#   135   — RPC endpoint mapper (cluster API / admin RPC)
#   49152-65535 — Windows dynamic RPC (cluster health service + AG coordination)
#
# Note: asg-sqlcluster is SEPARATE from asg-win-<suffix>, which is used for
# internet-facing 1433 access. Do not merge them — their scopes differ.
#
# Prerequisite: both Windows VMs must exist (NIC resolution uses az vm nic list).
# =========================================================

ASG_NAME="$CLUSTER_ASG_NAME"   # asg-sqlcluster

resource_exists() { eval "$1" >/dev/null 2>&1; }

# =========================================================
# CREATE THE APPLICATION SECURITY GROUP
# =========================================================
if resource_exists "az network asg show --resource-group $RESOURCE_GROUP --name $ASG_NAME"; then
  echo -e "${YELLOW}ASG $ASG_NAME already exists.${NC}"
else
  echo -e "${BLUE}Creating ASG $ASG_NAME...${NC}"
  az network asg create \
    --resource-group "$RESOURCE_GROUP" \
    --name "$ASG_NAME" \
    --location "$LOCATION"
fi

ASG_ID=$(az network asg show \
  --resource-group "$RESOURCE_GROUP" \
  --name "$ASG_NAME" \
  --query id -o tsv)

# =========================================================
# ATTACH BOTH WINDOWS NODE NICS TO THE ASG
# =========================================================
for VM in "$WIN_VM_NAME" "$WIN_VM_NAME_2"; do
  echo -e "${BLUE}Resolving NIC for $VM...${NC}"

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

  if az network nic ip-config show \
      --resource-group "$RESOURCE_GROUP" \
      --nic-name "$NIC" \
      --name "$IPCONFIG" \
      --query "applicationSecurityGroups[].id" \
      -o tsv 2>/dev/null | grep -qx "$ASG_ID"; then
    echo -e "${YELLOW}  $NIC already in $ASG_NAME.${NC}"
  else
    echo -e "${BLUE}  Attaching $NIC to $ASG_NAME...${NC}"
    az network nic ip-config update \
      --resource-group "$RESOURCE_GROUP" \
      --nic-name "$NIC" \
      --name "$IPCONFIG" \
      --application-security-groups "$ASG_ID"
  fi
done

# =========================================================
# ADD CLUSTER NSG RULES TO BOTH WINDOWS NSGS
# ---------------------------------------------------------
# Rule name -> "priority,protocol,port-range"
# Priorities 100-140 sit above the existing client-IP rules (1000+) so cluster
# traffic is admitted before the more specific admin rules are evaluated.
# =========================================================
CLUSTER_RULES=(
"Allow-WSFC-SQL-1433|100|Tcp|1433"
"Allow-WSFC-HADR-5022|110|Tcp|5022"
"Allow-WSFC-Heartbeat-3343|120|*|3343"
"Allow-WSFC-RPC-135|130|Tcp|135"
"Allow-WSFC-DynRPC|140|Tcp|49152-65535"
)

for NSG in "$WIN_NSG_NAME" "$WIN2_NSG_NAME"; do

    if ! resource_exists "az network nsg show --resource-group $RESOURCE_GROUP --name $NSG"; then
        echo -e "${YELLOW}NSG $NSG not found — skipping.${NC}"
        continue
    fi

    for RULE in "${CLUSTER_RULES[@]}"; do

        IFS='|' read -r RULE_NAME PRIORITY PROTO PORTS <<< "$RULE"

        if resource_exists "az network nsg rule show --resource-group $RESOURCE_GROUP --nsg-name $NSG --name $RULE_NAME"; then
            echo -e "${YELLOW}Rule $RULE_NAME already exists on $NSG.${NC}"
            continue
        fi

        echo -e "${BLUE}Creating $RULE_NAME on $NSG (priority $PRIORITY, ports $PORTS)...${NC}"

        az network nsg rule create \
            --resource-group "$RESOURCE_GROUP" \
            --nsg-name "$NSG" \
            --name "$RULE_NAME" \
            --priority "$PRIORITY" \
            --direction Inbound \
            --access Allow \
            --protocol "$PROTO" \
            --source-asgs "$ASG_ID" \
            --source-port-ranges "*" \
            --destination-port-ranges "$PORTS" \
            --destination-asgs "$ASG_ID"

    done

done

echo -e "${GREEN}==========================================${NC}"
echo -e "${GREEN}WSFC cluster NSG rules configured.${NC}"
echo -e "${GREEN}  ASG:  $ASG_NAME${NC}"
echo -e "${GREEN}  NSGs: $WIN_NSG_NAME, $WIN2_NSG_NAME${NC}"
echo -e "${GREEN}  Rules: Allow-WSFC-SQL-1433 (100), Allow-WSFC-HADR-5022 (110),${NC}"
echo -e "${GREEN}         Allow-WSFC-Heartbeat-3343 (120), Allow-WSFC-RPC-135 (130),${NC}"
echo -e "${GREEN}         Allow-WSFC-DynRPC (140)${NC}"
echo -e "${GREEN}==========================================${NC}"
